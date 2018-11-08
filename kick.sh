#!/bin/bash

BASE_DIR=${HOME}
BUILD_DIR=${BASE_DIR}/kick
LOG_DIR=${BUILD_DIR}/logs
DATE=$(date +%Y%m%d)
LOG=${LOG_DIR}/kick-${DATE}.log

LINUX_DIR=${BASE_DIR}/linux
LINUX_BRANCHES="4.14 4.19"
ACTIVE_LINUX_BRANCH="4.19"

YOCTO_BRANCH="thud"
YOCTO_LAYERS="meta-openembedded meta-qt5"
YOCTO_DIR=${BASE_DIR}/poky-${YOCTO_BRANCH}
YOCTO_COMMIT_LOG="${LOG_DIR}/yocto-commits-${DATE}"

BOARDS="atom bbb duovero odroid-c2 wandboard"

update_linux_repos()
{
    if [ ! -d ${LINUX_DIR}/linux-stable ]; then
        echo "Directory not found: ${LINUX_DIR}/linux-stable" >> ${LOG}
        exit 1
    fi

    cd ${LINUX_DIR}/linux-stable

    for branch in ${LINUX_BRANCHES}
    do
        git checkout linux-${branch}.y >> ${LOG} 2>&1
        git pull >> ${LOG} 2>&1
        logfile=${LOG_DIR}/${branch}-${DATE}
        git log | head -1 | awk '{ print $2 }' > ${logfile}
        version=${branch}.$(grep SUBLEVEL Makefile | head -1 | awk '{ print $3 }')
	echo ${version} >> ${logfile}
    done
}

update_yocto_repos()
{
    if [ ! -d ${YOCTO_DIR} ]; then
        echo "Directory not found: ${YOCTO_DIR}" >> ${LOG}
        exit 1
    fi

    cd ${YOCTO_DIR}

    echo "Checking poky-${YOCTO_BRANCH}" >> ${LOG}
    git checkout ${YOCTO_BRANCH} >> ${LOG} 2>&1
    git pull >> ${LOG} 2>&1
    echo "poky $(git log --oneline | head -1 | awk '{ print $1; }')" > ${YOCTO_COMMIT_LOG}

    for layer in ${YOCTO_LAYERS}
    do
        if [ ! -d ${layer} ]; then
            echo "Path not found: ${layer}"
            exit 1
        fi

        cd ${layer}
        echo "Checking ${layer}" >> ${LOG}
        git checkout ${YOCTO_BRANCH} >> ${LOG} 2>&1
        git pull >> ${LOG} 2>&1
        echo "${layer} $(git log --oneline | head -1 | awk '{ print $1; }')" >> ${YOCTO_COMMIT_LOG}
        cd ..
    done
}

check_kernels()
{
    for board in ${BOARDS}
    do
        if [ ! -d "${BASE_DIR}/${board}/meta-${board}" ]; then
            echo "Directory not found: ${BASE_DIR}/${board}/meta-${board}" >> ${LOG}
            exit 1
        fi

        recipe_path="${BASE_DIR}/${board}/meta-${board}/recipes-kernel/linux"

        if [ ! -d ${recipe_path} ]; then
            echo "Directory not found: ${recipe_path}" >> ${LOG}
            exit 1
        fi

        cd $recipe_path

        for branch in ${LINUX_BRANCHES};
        do
            if [ ! -f linux-stable_$branch.bb ]; then
                echo "Recipe not found: linux-stable_$branch.bb"
                exit 1
            fi

            latest_commit=$(cat ${LOG_DIR}/${branch}-${DATE} | head -1)
            latest_version=$(cat ${LOG_DIR}/${branch}-${DATE} | tail -1)

            current_commit=$(grep SRCREV linux-stable_${branch}.bb | awk '{ print $3 }' | tr -d '"')
            current_version=$(grep PV linux-stable_${branch}.bb | awk '{ print $3 }' | tr -d '"')

            if [ "${latest_commit}" = "${current_commit}" ]; then
                echo "$board kernel $branch OK" >> ${LOG}
            else
                echo "$board kernel $branch STALE" >> ${LOG}
            fi
        done
    done
}

update_meta_layer_readmes()
{
    for board in ${BOARDS}
    do
        readme="${BASE_DIR}/${board}/meta-${board}/README.md"

        commit=$(grep poky ${YOCTO_COMMIT_LOG})

        grep -q -e "${commit}" ${readme}

        if [ $? -eq 1 ]; then
            echo "Updating ${readme} for poky commit" >> ${LOG}
            sed -i "s:^    poky.*:    ${commit}:" ${readme}
        fi

        for layer in ${YOCTO_LAYERS}
        do
            grep -q ${layer} ${readme}

            if [ $? -eq 0 ]; then
                commit=$(grep ${layer} ${YOCTO_COMMIT_LOG})

                grep -q -e "${commit}" ${readme}

                if [ $? -eq 1 ]; then
                    echo "${board} ${layer} UPDATED" >> ${LOG}
                    sed -i "s:^    ${layer}.*:    ${commit}:" ${readme}
                fi
            fi
        done
    done
}

update_meta_layer_kernels()
{
    for branch in ${LINUX_BRANCHES}
    do
        latest_commit=$(cat ${LOG_DIR}/${branch}-${DATE} | head -1)
        latest_version=$(cat ${LOG_DIR}/${branch}-${DATE} | tail -1)

        for board in ${BOARDS}
        do
            grep -q "${board} kernel ${branch} STALE" $LOG

            if [ $? -eq 0 ]; then
                recipe_path="${BASE_DIR}/${board}/meta-${board}/recipes-kernel/linux"

                echo "Updating recipe ${recipe_path}/linux-stable_${branch}.bb" >> ${LOG}
                sed -i "s:^SRCREV.*:SRCREV = \"${latest_commit}\":" ${recipe_path}/linux-stable_${branch}.bb
                sed -i "s:^PV.*:PV = \"${latest_version}\":" ${recipe_path}/linux-stable_${branch}.bb
            fi
        done
    done
}

rebuild_active_kernels()
{
    for board in ${BOARDS}
    do
        grep -q "${board} kernel ${branch} STALE" $LOG

        if [ $? -eq 0 ]; then
            echo "Rebuilding console image for ${board}" >> ${LOG}
            result=$( source ${YOCTO_DIR}/oe-init-build-env ${BASE_DIR}/${board}/build && \
              bitbake -c cleansstate console-image && \
              bitbake -c cleansstate virtual/kernel && \
              bitbake console-image && \
              echo "Finished building console image for ${board}" >> ${LOG}; )

            echo "Result $? : $result" >> ${LOG}
        fi
    done
}

cleanup_old_logs()
{
    find ${LOG_DIR} -mtime +1 -delete
}

########################################
# the main flow
########################################

mkdir -p ${LOG_DIR}

if [ ! -d ${LOG_DIR} ]; then
    echo "Error creating kick log directory"
    exit 1
fi

echo "kick start: $(date)" >> ${LOG}

update_linux_repos

update_yocto_repos

check_kernels

update_meta_layer_readmes

update_meta_layer_kernels

rebuild_active_kernels

cleanup_old_logs

echo "kick done: $(date)" >> ${LOG}

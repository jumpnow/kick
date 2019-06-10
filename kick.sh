#!/bin/bash

BASE_DIR=${HOME}
BUILD_DIR=${BASE_DIR}/kick
LOG_DIR=${BUILD_DIR}/logs
DATE=$(date +%Y%m%d)
LOG=${LOG_DIR}/kick-${DATE}.log

LINUX_DIR=${BASE_DIR}/linux
LINUX_BRANCHES="4.19 5.1"
ACTIVE_LINUX_BRANCH="5.1"

RPI_LINUX_BRANCH="4.19"

YOCTO_BRANCH="warrior"
YOCTO_LAYERS="meta-openembedded meta-qt5 meta-raspberrypi meta-security"
BOARDS="atom bbb duovero odroid-c2 rpi wandboard"

YOCTO_DIR=${BASE_DIR}/poky-${YOCTO_BRANCH}
YOCTO_COMMIT_LOG="${LOG_DIR}/yocto-commits-${DATE}"

update_linux_stable()
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

update_linux_rpi()
{
    if [ ! -d ${LINUX_DIR}/linux-rpi ]; then
        echo "Directory not found: ${LINUX_DIR}/linux-rpi" >> ${LOG}
        exit 1
    fi

    cd ${LINUX_DIR}/linux-rpi

    branch=${RPI_LINUX_BRANCH}
    git checkout rpi-${branch}.y >> ${LOG} 2>&1
    git pull >> ${LOG} 2>&1
    logfile=${LOG_DIR}/rpi-${branch}-${DATE}
    git log | head -1 | awk '{ print $2 }' > ${logfile}
    version=${branch}.$(grep SUBLEVEL Makefile | head -1 | awk '{ print $3 }')
    echo ${version} >> ${logfile}
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

        if [ ${board} = "rpi" ]; then
            branch="${RPI_LINUX_BRANCH}"

            if [ ! -f linux-raspberrypi_${branch}.bbappend ]; then
                echo "Recipe not found: linux-raspberrypi_${branch}.bbappend"
                exit 1
            fi

            latest_commit=$(cat ${LOG_DIR}/rpi-${branch}-${DATE} | head -1)
            latest_version=$(cat ${LOG_DIR}/rpi-${branch}-${DATE} | tail -1)

            current_commit=$(grep SRCREV linux-raspberrypi_${branch}.bbappend | awk '{ print $3 }' | tr -d '"')
            current_version=$(grep LINUX_VERSION linux-raspberrypi_${branch}.bbappend | awk '{ print $3 }' | tr -d '"')

            if [ "${latest_commit}" = "${current_commit}" ]; then
                echo "$board kernel $branch OK" >> ${LOG}
            else
                echo "$board kernel $branch STALE" >> ${LOG}
            fi
        else
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
        fi
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
            echo "${board} poky UPDATED" >> ${LOG}
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
            [ ${board} = "rpi" ] && continue

            grep -q "${board} kernel ${branch} STALE" $LOG

            if [ $? -eq 0 ]; then
                recipe_path="${BASE_DIR}/${board}/meta-${board}/recipes-kernel/linux"
                echo "Updating recipe ${recipe_path}/linux-stable_${branch}.bb" >> ${LOG}
                sed -i "s:^SRCREV.*:SRCREV = \"${latest_commit}\":" ${recipe_path}/linux-stable_${branch}.bb
                sed -i "s:^PV.*:PV = \"${latest_version}\":" ${recipe_path}/linux-stable_${branch}.bb
            fi
        done
    done

    branch=${RPI_LINUX_BRANCH}
    board="rpi"

    grep -q "${board} kernel ${branch} STALE" $LOG

    if [ $? -eq 0 ]; then
        latest_commit=$(cat ${LOG_DIR}/rpi-${branch}-${DATE} | head -1)
        latest_version=$(cat ${LOG_DIR}/rpi-${branch}-${DATE} | tail -1)

        recipe_path="${BASE_DIR}/${board}/meta-${board}/recipes-kernel/linux"
        echo "Updating recipe ${recipe_path}/linux-raspberrypi_${branch}.bbappend" >> ${LOG}
        sed -i "s:^SRCREV.*:SRCREV = \"${latest_commit}\":" ${recipe_path}/linux-raspberrypi_${branch}.bbappend
        sed -i "s:^LINUX_VERSION.*:LINUX_VERSION = \"${latest_version}\":" ${recipe_path}/linux-raspberrypi_${branch}.bbappend
    fi
}

rebuild_images()
{
    for board in ${BOARDS}
    do
        if [ ${board} = "rpi" ]; then
            grep -q "${board} kernel ${RPI_LINUX_BRANCH} STALE" $LOG
        else
            grep -q "${board} kernel ${ACTIVE_LINUX_BRANCH} STALE" $LOG
        fi

        if [ $? -eq 0 ]; then
            echo "Rebuilding kernel and console image for ${board}" >> ${LOG}
            result=$( source ${YOCTO_DIR}/oe-init-build-env ${BASE_DIR}/${board}/build && \
              bitbake -c cleansstate console-image && \
              bitbake -c cleansstate virtual/kernel && \
              bitbake console-image && \
              echo "Finished building console image for ${board}" >> ${LOG}; )

            if [ $? -ne 0 ]; then
                echo "Result $? : $result" >> ${LOG}
            fi
        else
            # only building console images so don't rebuild if only meta-qt5 changes
            grep "UPDATED" $LOG | grep -v meta-qt5 | grep -q "${board}"

            if [ $? -eq 0 ]; then
                echo "Rebuilding console image for ${board}" >> ${LOG}
                result=$( source ${YOCTO_DIR}/oe-init-build-env ${BASE_DIR}/${board}/build && \
                  bitbake -c cleansstate console-image && \
                  bitbake console-image && \
                  echo "Finished building console image for ${board}" >> ${LOG}; )

                if [ $? -ne 0 ]; then
                    echo "Result $? : $result" >> ${LOG}
                fi
            fi
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

echo "kick start: $(date)" > ${LOG}

update_linux_stable

update_linux_rpi

update_yocto_repos

check_kernels

update_meta_layer_readmes

update_meta_layer_kernels

rebuild_images

cleanup_old_logs

echo "kick done: $(date)" >> ${LOG}

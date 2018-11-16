# kick

I run the script from cron

    # m h  dom mon dow   command
    0 5 * * * /home/scott/kick/kick.sh

Commits and pushes to meta-layer repos are still manual after review.

An example daily log where nothing much happened

    ~$ cat kick/logs/kick-20181116.log
    kick start: Fri Nov 16 05:32:01 EST 2018
    Switched to branch 'linux-4.14.y'
    Your branch is up-to-date with 'origin/linux-4.14.y'.
    Already up-to-date.
    Switched to branch 'linux-4.19.y'
    Your branch is up-to-date with 'origin/linux-4.19.y'.
    Already up-to-date.
    Checking poky-thud
    Already on 'thud'
    Your branch is up-to-date with 'origin/thud'.
    From git://git.yoctoproject.org/poky
     + ba4226e...b6fa510 master-next -> origin/master-next  (forced update)
     * [new tag]         thud-20.0.0 -> thud-20.0.0
     * [new tag]         yocto-2.6  -> yocto-2.6
    Already up-to-date.
    Checking meta-openembedded
    Already on 'thud'
    Your branch is up-to-date with 'origin/thud'.
    Already up-to-date.
    Checking meta-qt5
    Already on 'thud'
    Your branch is up-to-date with 'origin/thud'.
    Already up-to-date.
    atom kernel 4.14 OK
    atom kernel 4.19 OK
    bbb kernel 4.14 OK
    bbb kernel 4.19 OK
    duovero kernel 4.14 OK
    duovero kernel 4.19 OK
    odroid-c2 kernel 4.14 OK
    odroid-c2 kernel 4.19 OK
    wandboard kernel 4.14 OK
    wandboard kernel 4.19 OK
    kick done: Fri Nov 16 05:32:15 EST 2018


#!/bin/bash

set -e

clone() {
    for PROJECT in ${PROJECT_LIST[@]}; do
        if [ -d ${PROJECT} ]; then
            echo -e "\x1B[92m${PROJECT}\x1B[0m already exist, performing git pull"
            cd ${PROJECT}
            git checkout ${BRANCH}
            git pull
            cd ../
        else
            echo -e "Cloning \x1B[92m${PROJECT}\x1B[0m repo"
            case ${PROJECT} in
                che-parent|che-dependencies|che-lib|che)
                    echo -e "Cloning \x1B[92m${PROJECT}\x1B[0m repo from \x1B[92mECLIPSE\x1B[0m"
                    git clone git@github.com:eclipse/${PROJECT}.git
                    ;;
                *)
                    echo -e "Cloning \x1B[92m${PROJECT}\x1B[0m repo from \x1B[92mCODENVY\x1B[0m"
                    git clone git@github.com:codenvy/${PROJECT}.git
                    ;;
            esac
            cd ${PROJECT}
            git checkout ${BRANCH}
            cd ../
        fi
    done
}

resolveVersions() {
    cd onpremises
    CURRENT_VERSION=`mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version|grep -Ev '(^\[|Download\w+:)' | sed 's/-SNAPSHOT//g'`
    MAJOR=`echo ${CURRENT_VERSION} | cut -d '-' -f 1`
    MARKENTING=`echo ${CURRENT_VERSION} | cut -d '-' -f 2 | sed 's/[0-9]*//g'`
    DEV=`echo ${CURRENT_VERSION} | cut -d '-' -f 2 | sed 's/RC//g'`
    VERSION="${MAJOR}-${MARKENTING}${DEV}"
    NEXT_DEV_VERSION="${MAJOR}-${MARKENTING}$((${DEV}+1))-SNAPSHOT"
    echo -e "\x1B[92m############### RELEASE VERSION: ${VERSION}\x1B[0m"
    echo -e "\x1B[92m############### NEXT DEV VERSION: ${NEXT_DEV_VERSION}\x1B[0m"
    cd ../
}

setTagVersions() {
    echo -e "\x1B[92m############### Set tag versions.\x1B[0m"
    NEW_VER=$1 && shift
    PROP_LIST=($@)

    for i in ${PROP_LIST[@]}
    do
        version_old=$(grep -m 1 ${i} pom.xml | awk '{print $1}')
        version_new="<${i}>${NEW_VER}</${i}>"
        sed -i -e "s#$version_old#$version_new#" pom.xml
    done
    mvn scm:update  scm:checkin scm:update  -Dincludes=pom.xml  -Dmessage="RELEASE:Set tag versions" -DpushChanges=true
}

setNextDevVersions() {
    echo -e "\x1B[92m############### Set next dev versions.\x1B[0m"
    NEW_VER=$1 && shift
    PROP_LIST=($@)

    for i in ${PROP_LIST[@]}
    do
        version_old=$(grep -m 1 ${i} pom.xml | awk '{print $1}')
        version_new="<${i}>${NEW_VER}</${i}>"
        sed -i -e "s#$version_old#$version_new#" pom.xml
    done
    mvn scm:update  scm:checkin scm:update  -Dincludes=pom.xml  -Dmessage="RELEASE:Set next dev versions" -DpushChanges=true
}

setParentTag() {
        echo -e "\x1B[92m############### Set tag of parent pom in $1\x1B[0m"
            mvn versions:update-parent versions:commit -DparentVersion=[$2]
            mvn scm:update scm:checkin scm:update -Dincludes=pom.xml -Dmessage="RELEASE:Set tag of parent pom" -DpushChanges=true
}

setParentNextDev() {
        echo -e "\x1B[92m############### Set next development version of parent pom in $1\x1B[0m"
            mvn versions:update-parent  versions:commit -DallowSnapshots=true -DparentVersion=[$2]
            mvn scm:update scm:checkin scm:update -Dincludes=pom.xml -Dmessage="RELEASE:Set next development version of parent pom" -DpushChanges=true
}

releaseProject() {
        echo -e "\x1B[92m############### Release: $1\x1B[0m"
        mvn release:prepare -Dresume=false -Dtag=$2 -DdevelopmentVersion=$3 -DreleaseVersion=$2 "-Darguments=-DskipTests=true -Dskip-validate-sources -Dgpg.passphrase=${GPG_PASSPHRASE}"
        mvn release:perform "-Darguments=-DskipTests=true -Dskip-validate-sources -Dgpg.passphrase=${GPG_PASSPHRASE}"
}

setCheDashboardTag() {
        echo "set che-dashboard tag $1"
        sed -i -e "s/eclipse\/che.git#master/eclipse\/che.git#$1/" bower.json
        mvn scm:update  scm:checkin scm:update  -Dincludes=bower.json  -Dmessage="RELEASE:Set tag version of che-dashboard" -DpushChanges=true
}

setCheDashboardNextDev() {
        echo "set che-dashboard next dev version #master"
        sed -i -e "s/eclipse\/che.git#$1/eclipse\/che.git#master/" bower.json
        mvn scm:update  scm:checkin scm:update  -Dincludes=bower.json  -Dmessage="RELEASE:Set next dev version of che-dashboard" -DpushChanges=true
}

release() {
    for project in ${PROJECT_LIST[@]}
    do
        cd ${project}
        if [ ${project} == "che-parent" ]; then
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            mvn clean install
        elif [ ${project} == "che" ]; then
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${CHE_PROPERTIES_LIST[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${CHE_PROPERTIES_LIST[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
            mvn clean install -N
        elif [ ${project} == "che-dependencies" ]; then
            setParentTag ${project} ${VERSION}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
            mvn clean install
        elif [ ${project} == "codenvy-depmgt" ]; then
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${HOSTED_PROPERTIES_LIST[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${HOSTED_PROPERTIES_LIST[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
            mvn clean install
        elif [ ${project} == "dashboard" ]; then
            setParentTag ${project} ${VERSION}
            setCheDashboardTag ${VERSION}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setCheDashboardNextDev ${VERSION}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
        else
            setParentTag ${project} ${VERSION}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
        fi
        cd ..
    done
}

cleanUp() {
    for project in ${PROJECT_LIST[@]}
    do
        rm -rf ${project}
    done
}

performRelease() {
    cleanUp
    clone
    resolveVersions
    release
}

setNextMajor() {
    NEXT_MAJOR="4.0.0-beta-1-SNAPSHOT"
    for PROJECT in ${PROJECT_LIST[@]}; do
        cd ${PROJECT}
        if [ ${PROJECT} == "che-parent" ]; then
            mvn versions:set -DnewVersion=${NEXT_MAJOR} -DgenerateBackupPoms=false
            mvn scm:update  scm:checkin scm:update  -Dincludes=.  -Dmessage="Set Next Major version" -DpushChanges=true
            mvn clean install
        elif [ ${PROJECT} == "che-depmgt" ]; then
            mvn versions:set -DnewVersion=${NEXT_MAJOR} -DgenerateBackupPoms=false
            for i in ${CHE_PROPERTIES_LIST[@]}
            do
            version_old=$(grep -m 1 ${i} pom.xml | awk '{print $1}')
            version_new="<${i}>${NEXT_MAJOR}</${i}>"
            sed -i -e "s#$version_old#$version_new#" pom.xml
            done
            mvn versions:update-parent  -DparentVersion=[${NEXT_MAJOR}] -DallowSnapshots=true -DgenerateBackupPoms=false
            mvn scm:update  scm:checkin scm:update  -Dincludes=. -Dmessage="Set Next Major version" -DpushChanges=true
            mvn clean install
        elif [ ${PROJECT} == "codenvy-depmgt" ]; then
            mvn versions:set -DnewVersion=${NEXT_MAJOR} -DgenerateBackupPoms=false
            for i in ${HOSTED_PROPERTIES_LIST[@]}
            do
            version_old=$(grep -m 1 ${i} pom.xml | awk '{print $1}')
            version_new="<${i}>${NEXT_MAJOR}</${i}>"
            sed -i -e "s#$version_old#$version_new#" pom.xml
            done
            mvn versions:update-parent  -DparentVersion=[${NEXT_MAJOR}] -DallowSnapshots=true -DgenerateBackupPoms=false
            mvn scm:update  scm:checkin scm:update  -Dincludes=. -Dmessage="Set Next Major version" -DpushChanges=true
            mvn clean install
        else
            mvn versions:set -DnewVersion=${NEXT_MAJOR} -DgenerateBackupPoms=false
            mvn versions:update-parent  -DparentVersion=[${NEXT_MAJOR}] -DallowSnapshots=true -DgenerateBackupPoms=false
            mvn scm:update  scm:checkin scm:update  -Dincludes=.  -Dmessage="Set Next Major version" -DpushChanges=true
        fi
        cd ../
    done
}

CHE_PROPERTIES_LIST=(
 che.lib.version )

HOSTED_PROPERTIES_LIST=(
che.lib.version
che.version
#codenvy.analytics.version
codenvy.cli.version
codenvy.cloud-ide.version
codenvy.dashboard.version
codenvy.factory.version
codenvy.hosted-infrastructure.version
codenvy.im.version
codenvy.odyssey.version
codenvy.onpremises.version
codenvy.platform-api-client-java.version
codenvy.plugins.version )

# KEEP CORRECT ORDER!
#PROJECT_LIST=(
#che-parent
#che-dependencies
#che-lib
#che
#codenvy-depmgt
#hosted-infrastructure
#plugins
#dashboard
#odyssey
#factory
#cloud-ide
#platform-api-client-java
#cli
#cdec
#onpremises
#che-installer )
PROJECT_LIST=("${@:3}")
GPG_PASSPHRASE=$2
############################

$1

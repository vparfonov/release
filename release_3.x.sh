#!/bin/bash

set -e

clone() {
    for PROJECT in ${PROJECT_LIST[@]}; do
        if [ -d ${PROJECT} ]; then
            echo -e "\x1B[92m${PROJECT} already exist, performing git pull\x1B[0m"
            cd ${PROJECT}
            git pull
            cd ../
        else
            echo -e "\x1B[92mCloning ${PROJECT} repo\x1B[0m"
                git clone git@github.com:codenvy/${PROJECT}.git
                cd ${PROJECT}
                git checkout ${BRANCH}
                cd ../
        fi
    done
}

resolveVersions() {
    cd onpremises
    CURRENT_VERSION=`mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version|grep -Ev '(^\[|Download\w+:)' | cut -d '-' -f 1`
    MAJOR=`echo ${CURRENT_VERSION} | cut -d '.' -f 1`
    MARKENTING=`echo ${CURRENT_VERSION} | cut -d '.' -f 2`
    DEV=`echo ${CURRENT_VERSION} | cut -d '.' -f 3`
    VERSION="${MAJOR}.${MARKENTING}.${DEV}"
    NEXT_DEV_VERSION="${MAJOR}.${MARKENTING}.$((${DEV}+1))-SNAPSHOT"
    echo -e "\x1B[92m############### RELEASE VERSION: ${VERSION}\x1B[0m"
    echo -e "\x1B[92m############### NEXT DEV VERSION: ${NEXT_DEV_VERSION}\x1B[0m"
    cd ../
}
#ssss
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
    mvn scm:update  scm:checkin scm:update  -Dincludes=pom.xml  -Dmessage="RELEASE:Set tag versions" -DpushChanges=true -DscmVersionType=branch -DscmVersion=${BRANCH}
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
    mvn scm:update  scm:checkin scm:update  -Dincludes=pom.xml  -Dmessage="RELEASE:Set next dev versions" -DpushChanges=true -DscmVersionType=branch -DscmVersion=${BRANCH}
    mvn clean install
}

setParentTag() {
        echo -e "\x1B[92m############### Set tag of parent pom in $1\x1B[0m"
            mvn versions:update-parent versions:commit -DparentVersion=[$2]
            mvn scm:update scm:checkin scm:update -Dincludes=pom.xml -Dmessage="RELEASE:Set tag of parent pom" -DpushChanges=true -DscmVersionType=branch -DscmVersion=${BRANCH}
}

setParentNextDev() {
        echo -e "\x1B[92m############### Set next development version of parent pom in $1\x1B[0m"
            mvn versions:update-parent  versions:commit -DallowSnapshots=true -DparentVersion=[$2]
            mvn scm:update scm:checkin scm:update -Dincludes=pom.xml -Dmessage="RELEASE:Set next development version of parent pom" -DpushChanges=true -DscmVersionType=branch -DscmVersion=${BRANCH}
}

releaseProject() {
        echo -e "\x1B[92m############### Release: $1\x1B[0m"
        mvn --batch-mode release:prepare release:perform -Dresume=false -Darguments=-Dgpg.passphrase=Ya3Waa2O -Dtag=$2 -DdevelopmentVersion=$3 -DreleaseVersion=$2
}

release() {
    for project in ${PROJECT_LIST[@]}
    do
        cd ${project}
        if [ ${project} == "che-depmgt" ]; then
            setTagVersions ${VERSION} ${CHE_PROPERTIES_LIST[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${CHE_PROPERTIES_LIST[@]}
        elif [ ${project} == "codenvy-depmgt" ]; then
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${HOSTED_PROPERTIES_LIST[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${HOSTED_PROPERTIES_LIST[@]}
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
    NEXT_MAJOR="3.13.0-SNAPSHOT"
    for PROJECT in ${PROJECT_LIST[@]}; do
        cd ${PROJECT}
        if [ ${PROJECT} == "che-depmgt" ]; then
            mvn versions:set -DnewVersion=${NEXT_MAJOR} -DgenerateBackupPoms=false
            for i in ${CHE_PROPERTIES_LIST[@]}
            do
            version_old=$(grep -m 1 ${i} pom.xml | awk '{print $1}')
            version_new="<${i}>${NEXT_MAJOR}</${i}>"
            sed -i -e "s#$version_old#$version_new#" pom.xml
            done
            mvn scm:update  scm:checkin scm:update  -Dincludes=. -Dmessage="Set Next Major version" -DpushChanges=true -DscmVersionType=branch -DscmVersion=${BRANCH}
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
            mvn scm:update  scm:checkin scm:update  -Dincludes=. -Dmessage="Set Next Major version" -DpushChanges=true -DscmVersionType=branch -DscmVersion=${BRANCH}
            mvn clean install
        else
            mvn versions:set -DnewVersion=${NEXT_MAJOR} -DgenerateBackupPoms=false
            mvn versions:update-parent  -DparentVersion=[${NEXT_MAJOR}] -DallowSnapshots=true -DgenerateBackupPoms=false
            mvn scm:update  scm:checkin scm:update  -Dincludes=.  -Dmessage="Set Next Major version" -DpushChanges=true -DscmVersionType=branch -DscmVersion=${BRANCH}
        fi
        cd ../
    done
}

CHE_PROPERTIES_LIST=(
che.core.version
che.plugins.version
che.sdk.version
che.tutorials.version )

HOSTED_PROPERTIES_LIST=(
#codenvy.analytics.version
codenvy.cli.version
codenvy.cloud-ide.version
codenvy.factory.version
codenvy.hosted-infrastructure.version
codenvy.im.version
codenvy.odyssey.version
codenvy.platform-api-client-java.version
codenvy.plugins.version
codenvy.onpremises.version )

# KEEP CORRECT ORDER!
PROJECT_LIST=(
che-depmgt
che-core
che-plugins
che-tutorials
che
codenvy-depmgt
hosted-infrastructure
plugins
odyssey
factory
cloud-ide
platform-api-client-java
cli
cdec
onpremises )
##########################
BRANCH=3.x

$1

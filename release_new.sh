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
        fi
    done
}

resolveVersions() {
    CURRENT_VERSION=`mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version|grep -Ev '(^\[|Download\w+:)' | cut -d '-' -f 1`
    MAJOR=`echo ${CURRENT_VERSION} | cut -d '.' -f 1`
    MARKENTING=`echo ${CURRENT_VERSION} | cut -d '.' -f 2`
    DEV=`echo ${CURRENT_VERSION} | cut -d '.' -f 3`
    VERSION="${MAJOR}.${MARKENTING}.${DEV}"
    NEXT_DEV_VERSION="${MAJOR}.${MARKENTING}.$((${DEV}+1))-SNAPSHOT"
    echo -e "\x1B[92m############### RELEASE VERSION: ${VERSION}\x1B[0m"
    echo -e "\x1B[92m############### NEXT DEV VERSION: ${NEXT_DEV_VERSION}\x1B[0m"
}

setTagVersions(){
    echo -e "\x1B[92m############### Set tag versions in che-depmgt.\x1B[0m"
    for i in ${PROPERTIES_LIST[@]}
    do
        version_old=$(grep -m 1 ${i} pom.xml | awk '{print $1}')
        version_new="<${i}>$1</${i}>"
        cat $(pwd)/pom.xml
        sed -i "" -e "s#$version_old#$version_new#" pom.xml
    done
    mvn scm:update  scm:checkin scm:update  -Dincludes=pom.xml  -Dmessage="RELEASE:Set tag versions" -DpushChanges=false # change to true
}

setNextDevVersions(){
    echo -e "\x1B[92m############### Set next dev versions in che-depmgt.\x1B[0m"
    for i in ${PROPERTIES_LIST[@]}
    do
        version_old=$(grep -m 1 ${i} pom.xml | awk '{print $1}')
        version_new="<${i}>$1</${i}>"
        sed -i "" -e "s#$version_old#$version_new#" pom.xml
    done
    mvn scm:update  scm:checkin scm:update  -Dincludes=pom.xml  -Dmessage="RELEASE:Set next dev versions" -DpushChanges=false # change to true
}

setParentTag() {
        echo -e "\x1B[92m############### Set tag of parent pom in $1\x1B[0m"
        mvn versions:update-parent  versions:commit -DparentVersion=[$2]
        mvn scm:update  scm:checkin scm:update  -Dincludes=pom.xml  -Dmessage="RELEASE:Set tag of parent pom" -DpushChanges=false # change to true
}

setParentNextDev() {
        echo -e "\x1B[92m############### Set next development version of parent pom in $1\x1B[0m"
        mvn versions:update-parent  versions:commit -DallowSnapshots=true -DparentVersion=[$2]
        mvn scm:update  scm:checkin scm:update  -Dincludes=pom.xml  -Dmessage="RELEASE:Set next development version of parent pom" -DpushChanges=false # change to true
}


releaseProject(){
        echo -e "\x1B[92m############### Release: $1\x1B[0m"
        mvn --batch-mode release:prepare release:perform -Dresume=false -Darguments=-Dgpg.passphrase=Ya3Waa2O -Dtag=$2 -DdevelopmentVersion=$3 -DreleaseVersion=$2 -DdryRun=true
}

release() {
    for project in ${PROJECT_LIST[@]}
    do
        cd ${project}
        if [ ${project} == "che-depmgt" ]; then
            resolveVersions
            setTagVersions ${VERSION}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
#            setNextDevVersions ${NEXT_DEV_VERSION}
        else
#            setParentTag ${project} ${VERSION}
#            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
#            setParentNextDev ${project} ${NEXT_DEV_VERSION}
echo "esle"
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
    release
    cleanUp
}


PROPERTIES_LIST=( che.core.version che.plugins.version che.sdk.version che.tutorials.version codenvy.analytics.version codenvy.api-docs-ui.version codenvy.cli.version codenvy.cloud-ide.version codenvy.dashboard.version codenvy.factory.version codenvy.hosted-infrastructure.version codenvy.im.version codenvy.odyssey.version codenvy.platform-api-client-java.version codenvy.plugin-contribution.version codenvy.plugin.gae.version codenvy.plugin.hosted.version codenvy.plugins.version) #codenvy.dashboard2.version
# KEEP CORRECT ORDER!
PROJECT_LIST=( che-depmgt che-core che-plugins che-tutorials che hosted-infrastructure plugins plugin-hosted plugin-contribution plugin-gae odyssey factory user-dashboard swagger-ui cdec cloud-ide onpremises platform-api-client-java cli )

$1

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
if [[ -z "${RELEASE_VERSION}" ]] || [[ -z "${RELEASE_NEXT_VERSION}" ]] ; then
    cd onpremises
    CURRENT_VERSION=`mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version|grep -Ev '(^\[|Download\w+:)' | sed 's/-SNAPSHOT//g'`
    MAJOR=`echo ${CURRENT_VERSION} | cut -d '-' -f 1`
    MARKENTING=`echo ${CURRENT_VERSION} | cut -d '-' -f 2 | sed 's/[0-9]*//g'`
    DEV=`echo ${CURRENT_VERSION} | cut -d '-' -f 2 | sed 's/RC//g'`
    VERSION="${MAJOR}-${MARKENTING}${DEV}"
    NEXT_DEV_VERSION="${MAJOR}-${MARKENTING}$((${DEV}+1))-SNAPSHOT"
    cd ../
else
    VERSION=${RELEASE_VERSION}
    NEXT_DEV_VERSION=${RELEASE_NEXT_VERSION}
fi
    echo -e "\x1B[92m############### RELEASE VERSION: ${VERSION}\x1B[0m"
    echo -e "\x1B[92m############### NEXT DEV VERSION: ${NEXT_DEV_VERSION}\x1B[0m"
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
        sed -i -e "s/eclipse\/che.git#master/eclipse\/che.git#$1/" dashboard/bower.json
        mvn scm:update  scm:checkin scm:update  -Dincludes=bower.json  -Dmessage="RELEASE:Set tag version of che-dashboard" -DpushChanges=true
}

setCheDashboardNextDev() {
        echo "set che-dashboard next dev version #master"
        sed -i -e "s/eclipse\/che.git#$1/eclipse\/che.git#master/" dashboard/bower.json
        mvn scm:update  scm:checkin scm:update  -Dincludes=bower.json  -Dmessage="RELEASE:Set next dev version of che-dashboard" -DpushChanges=true
}

generateChangeLog() {
    if [ ! -z "${CHANGELOG_GITHUB_TOKEN}" ]; then
        github_changelog_generator --bugs-label  "**Issues fixed with 'bugs' label:**" --pr-label "**Pull requests merged:**" --enhancement-label  "**Issues with 'enhancement' label:**" --issues-label   "**Issues with no labels:**"
        mvn scm:update  scm:checkin scm:update  -Dincludes=. -Dmessage="Changelog for ${VERSION}" -DpushChanges=true
    else
        echo "CHANGELOG_GITHUB_TOKEN is not set, generate changelog skipping."
    fi
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
            generateChangeLog
        elif [ ${project} == "che-dependencies" ]; then
            setParentTag ${project} ${VERSION}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
            mvn clean install
        elif [ ${project} == "codenvy-docs" ]; then
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${CODENVY_DOCS_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${CODENVY_DOCS_VERSION_PROPERTIES[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
        elif [ ${project} == "codenvy" ]; then
            setParentTag ${project} ${VERSION}
            setCheDashboardTag ${VERSION}
            setTagVersions ${VERSION} ${ONPREM_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setCheDashboardNextDev ${VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${ONPREM_VERSION_PROPERTIES[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
            mvn clean install -N
            generateChangeLog
        elif [ ${project} == "customer-saas" ]; then
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${SAAS_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${SAAS_VERSION_PROPERTIES[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
            #generateChangeLog need to figure out why it is not work maybe due to private project
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

CHE_PROPERTIES_LIST=(
che.lib.version
che.version )

ONPREM_VERSION_PROPERTIES=(
che.lib.version
codenvy.docs.version
che.version )

SAAS_VERSION_PROPERTIES=(
che.version
onpremises.version )

CODENVY_DOCS_VERSION_PROPERTIES=(
che.docs.version )

# KEEP CORRECT ORDER!
#PROJECT_LIST=(
#che-parent
#che-dependencies
#che-lib
#che-docs
#che
#codenvy-docs
#codenvy
#customer-saas
#che-installer )
PROJECT_LIST=("${@:3}")
GPG_PASSPHRASE=$2
############################

$1

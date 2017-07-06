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
                che-parent|che-dependencies|che-lib|che|che-docs|che-archetypes)
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

updateParent() {
    mvn versions:update-parent  versions:commit -DallowSnapshots=true -DparentVersion=[$1]
}

updateDependencies() {
    NEW_VER=$1 && shift
    PROP_LIST=($@)

    for i in ${PROP_LIST[@]}
    do
        version_old=$(grep -m 1 ${i} pom.xml | awk '{print $1}')
        version_new="<${i}>${NEW_VER}</${i}>"
        sed -i -e "s#$version_old#$version_new#" pom.xml
    done
}

updateDashboardDependency() {
    sed -i -e "s/eclipse\/che.git#.*\",/eclipse\/che.git#$1\",/" dashboard/bower.json
}

createReleaseBranches() {
    if [ -z "${RELEASE_BRANCH_NAME}" ]; then
        echo "RELEASE_BRANCH_NAME is not set, exit."
        exit 2
    fi

    for PROJECT in ${PROJECT_LIST[@]}; do
        echo -e "\x1B[92m create release branch in ${PROJECT}\x1B[0m"
        cd ${PROJECT}
        git branch ${RELEASE_BRANCH_NAME}
        git push --set-upstream origin ${RELEASE_BRANCH_NAME}
        cd ../
    done
}

pushChanesWithMaven() {
    mvn scm:update scm:checkin scm:update -Dincludes=$1 -Dmessage="$2" -DpushChanges=true -D=scmVersionType=branch -DscmVersion=$3
}

update_dockerfiles_in_master() {
    # update dockerfiles
    cp -r  dockerfiles/cli/version/$VERSION dockerfiles/cli/version/$NEXT_TAG_VER
    sed -i -e "s#\(.*=codenvy/.*\)\(:.*\)#\1:$NEXT_TAG_VER#" dockerfiles/cli/version/${NEXT_TAG_VER}/images
    sed -i -e "s#.*#$VERSION#" dockerfiles/cli/version/latest.ver
}

setNextDevelopmentVersionInMaster() {
    if [ -z "${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}" ]; then
        echo "RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER is not set, exit."
        exit 2
    fi

    NEXT_TAG_VER=$(echo ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} | sed -e 's#-SNAPSHOT##')

    for PROJECT in ${PROJECT_LIST[@]}; do
        echo -e "\x1B[92m set next development version in master of ${PROJECT} project\x1B[0m"
        cd ${PROJECT}
        mvn versions:set -DnewVersion=${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} -DgenerateBackupPoms=false

        if [ ${PROJECT} == "che-parent" ]; then
            mvn clean install
        elif [ ${PROJECT} == "che-dependencies" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            mvn clean install
        elif [ ${PROJECT} == "che-lib" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
        elif [ ${PROJECT} == "che-docs" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
        elif [ ${PROJECT} == "che" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            updateDependencies ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${CHE_PROPERTIES_LIST[@]}
            mvn clean install -N
            # update dockerfiles
            cp -r  dockerfiles/cli/version/$VERSION dockerfiles/cli/version/$NEXT_TAG_VER
            sed -i -e "s#$VERSION#$NEXT_TAG_VER#" dockerfiles/cli/version/${NEXT_TAG_VER}/images
            sed -i -e "s#$VERSION#$NEXT_TAG_VER#" dockerfiles/cli/version/${NEXT_TAG_VER}/images-stacks
            sed -i -e "s#.*#$VERSION#" dockerfiles/cli/version/latest.ver
            sed -i -e "s#>.*-SNAPSHOT#>$RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER#" dockerfiles/lib/dto-pom.xml
        elif [ ${PROJECT} == "docs" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            updateDependencies ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${CODENVY_DOCS_VERSION_PROPERTIES[@]}
        elif [ ${PROJECT} == "codenvy" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            updateDependencies ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${ONPREM_VERSION_PROPERTIES[@]}
            updateDashboardDependency "master"
            mvn clean install -N
            update_dockerfiles_in_master
        elif [ ${PROJECT} == "saas" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            updateDependencies ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${SAAS_VERSION_PROPERTIES[@]}
            mvn clean install -N
            update_dockerfiles_in_master
        elif [ ${PROJECT} == "redhat" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            updateDependencies ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${REDHAT_VERSION_PROPERTIES[@]}
            mvn clean install -N
            update_dockerfiles_in_master
        elif [ ${PROJECT} == "silexica" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            updateDependencies ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${SILEXICA_VERSION_PROPERTIES[@]}
            mvn clean install -N
            update_dockerfiles_in_master
        elif [ ${PROJECT} == "che-archetypes" ]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            updateDependencies ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${ARCHETYPES_VERSION_PROPERTIES[@]}
        fi

        pushChanesWithMaven . "RELEASE: Set next development version" master
        cd ../
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
    local VERSION_OF_DEPS=$1 && shift
    local DEPS_LIST=($@)
    echo -e "\x1B[92m############### Set tag versions.\x1B[0m"
    updateDependencies $VERSION_OF_DEPS ${DEPS_LIST[@]}
    pushChanesWithMaven pom.xml "RELEASE: Set tag versions" ${RELEASE_BRANCH_NAME} 
}

setNextDevVersions() {
    local VERSION_OF_DEPS=$1 && shift
    local DEPS_LIST=($@)
    echo -e "\x1B[92m############### Set next dev versions.\x1B[0m"
    updateDependencies $VERSION_OF_DEPS ${DEPS_LIST[@]}
    pushChanesWithMaven pom.xml "RELEASE: Set next dev versions" ${RELEASE_BRANCH_NAME}
}

setParentTag() {
        echo -e "\x1B[92m############### Set tag of parent pom in $1\x1B[0m"
            updateParent $2
            pushChanesWithMaven pom.xml "RELEASE: Set tag of parent pom" ${RELEASE_BRANCH_NAME}
}

setParentNextDev() {
        echo -e "\x1B[92m############### Set next development version of parent pom in $1\x1B[0m"
        updateParent $2
        pushChanesWithMaven pom.xml "RELEASE: Set next development version of parent pom" ${RELEASE_BRANCH_NAME}
}

releaseProject() {
        echo -e "\x1B[92m############### Release: $1\x1B[0m"
        mvn release:prepare release:perform -Dresume=false -Dtag=$2 -DdevelopmentVersion=$3 -DreleaseVersion=$2 "-Darguments=-DskipTests=true -Dskip-validate-sources -Dgpg.passphrase=${GPG_PASSPHRASE} -Darchetype.test.skip=true"
}

setCheDashboardTag() {
        echo "set che-dashboard tag $1"
        updateDashboardDependency $1
        pushChanesWithMaven dashboard/bower.json "RELEASE: Set tag version of che-dashboard" ${RELEASE_BRANCH_NAME}
}

setCheDashboardNextDev() {
        echo "set che-dashboard next dev version #master"
        updateDashboardDependency "master"
        pushChanesWithMaven dashboard/bower.json "RELEASE: Set next dev version of che-dashboard" ${RELEASE_BRANCH_NAME}
}

set_tags_in_che_dockerfiles_for_release() {
        sed -i -e "s#nightly#$VERSION#" dockerfiles/base/scripts/base/images/images-bootstrap
        sed -i -e "s#nightly#$VERSION#" dockerfiles/base/scripts/base/images/images-utilities
        sed -i -e "s#.*#$VERSION#" dockerfiles/cli/version/latest.ver
        sed -i -e "s#-SNAPSHOT##" dockerfiles/lib/dto-pom.xml
        pushChanesWithMaven . "RELEASE: Set tags in Dockerfiles" ${RELEASE_BRANCH_NAME}
}

set_tags_in_codenvy_dockerfiles_for_release() {
        sed -i -e "s#:nightly#:$VERSION#" dockerfiles/cli/Dockerfile
        sed -i -e "s#.*#$VERSION#" dockerfiles/cli/version/latest.ver
        pushChanesWithMaven . "RELEASE: Set tags in Dockerfiles" ${RELEASE_BRANCH_NAME}
}

set_tags_in_codenvy_custom_assembly_dockerfiles_for_release() {
        sed -i -e "s#:nightly#:$VERSION#" dockerfiles/cli/Dockerfile
        sed -i -e "s#:nightly#:$VERSION#" dockerfiles/init/Dockerfile
        sed -i -e "s#.*#$VERSION#" dockerfiles/cli/version/latest.ver
        pushChanesWithMaven . "RELEASE: Set tags in Dockerfiles" ${RELEASE_BRANCH_NAME}
}

release() {
    for project in ${PROJECT_LIST[@]}
    do
        cd ${project}
        git checkout ${RELEASE_BRANCH_NAME}
        if [ ${project} == "che-parent" ]; then
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            mvn clean install
        elif [ ${project} == "che" ]; then
            set_tags_in_che_dockerfiles_for_release
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
        elif [ ${project} == "docs" ]; then
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${CODENVY_DOCS_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${CODENVY_DOCS_VERSION_PROPERTIES[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
        elif [ ${project} == "codenvy" ]; then
            set_tags_in_codenvy_dockerfiles_for_release
            setParentTag ${project} ${VERSION}
            setCheDashboardTag ${VERSION}
            setTagVersions ${VERSION} ${ONPREM_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setCheDashboardNextDev
            setNextDevVersions ${NEXT_DEV_VERSION} ${ONPREM_VERSION_PROPERTIES[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
            mvn clean install -N
        elif [ ${project} == "saas" ]; then
            set_tags_in_codenvy_custom_assembly_dockerfiles_for_release
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${SAAS_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${SAAS_VERSION_PROPERTIES[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
        elif [ ${project} == "redhat" ]; then
            set_tags_in_codenvy_custom_assembly_dockerfiles_for_release
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${REDHAT_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${REDHAT_VERSION_PROPERTIES[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
        elif [ ${project} == "silexica" ]; then
            set_tags_in_codenvy_custom_assembly_dockerfiles_for_release
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${SILEXICA_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${SILEXICA_VERSION_PROPERTIES[@]}
            setParentNextDev ${project} ${NEXT_DEV_VERSION}
        elif [ ${project} == "che-archetypes" ]; then
            setParentTag ${project} ${VERSION}
            setTagVersions ${VERSION} ${ARCHETYPES_VERSION_PROPERTIES[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setNextDevVersions ${NEXT_DEV_VERSION} ${ARCHETYPES_VERSION_PROPERTIES[@]}
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

prepareRelease() {
    cleanUp
    clone
    createReleaseBranches
    setNextDevelopmentVersionInMaster
}

performRelease() {
    cleanUp
    clone
    resolveVersions
    release
}

CHE_PROPERTIES_LIST=(
che.docs.version
che.lib.version
che.version )

ONPREM_VERSION_PROPERTIES=(
che.lib.version
codenvy.docs.version
che.version )

SAAS_VERSION_PROPERTIES=(
che.version
onpremises.version )

REDHAT_VERSION_PROPERTIES=(
che.version
codenvy.version )

SILEXICA_VERSION_PROPERTIES=(
che.version
codenvy.version )

CODENVY_DOCS_VERSION_PROPERTIES=(
che.docs.version )

ARCHETYPES_VERSION_PROPERTIES=(
che.version
codenvy.version )

# KEEP CORRECT ORDER!
#PROJECT_LIST=(
#che-parent
#che-dependencies
#che-lib
#che-docs
#che
#docs
#codenvy
#saas
#che-archetypes
#redhat
#silexica )

PROJECT_LIST=("${@:3}")
GPG_PASSPHRASE=$2
############################

$1

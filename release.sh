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
                che-ide-extension|che-ide-server-extension|che-plugin-menu|che-plugin-wizard|che-plugin-json|che-plugin-embedjs)
                    echo -e "Cloning \x1B[92m${PROJECT}\x1B[0m repo from \x1B[92mCHE-SAMPLES\x1B[0m"
                    git clone git@github.com:che-samples/${PROJECT}.git
                    ;;
                *)
                    echo -e "Cloning \x1B[92m${PROJECT}\x1B[0m repo from \x1B[92mECLIPSE\x1B[0m"
                    git clone git@github.com:eclipse/${PROJECT}.git
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

createBranches() {
    for PROJECT in ${PROJECT_LIST[@]}; do
        echo -e "\x1B[92m create $1 branch in ${PROJECT}\x1B[0m"
        cd ${PROJECT}
        git branch $1
        git push --set-upstream origin $1
        cd ../
    done
}

pushChanesWithMaven() {
    echo -e "\x1B[92m Push changes with maven into $3 branch\x1B[0m"
    mvn scm:update scm:checkin scm:update -Dincludes=$1 -Dmessage="$2" -DpushChanges=true -D=scmVersionType=branch -DscmVersion=$3
}

setNextDevelopmentVersionInMaster() {
    if [ -z "${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}" ]; then
        echo "RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER is not set, exit."
        exit 2
    fi
    resolveVersions
    NEXT_TAG_VER=$(echo ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} | sed -e 's#-SNAPSHOT##')

    for PROJECT in ${PROJECT_LIST[@]}; do
        echo -e "\x1B[92m set next development version in master of ${PROJECT} project\x1B[0m"
        cd ${PROJECT}
        git checkout $1
        mvn versions:set -DnewVersion=${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} -DgenerateBackupPoms=false

        if [ ${PROJECT} == "che-parent" ]; then
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
            git add .
        elif [[ ${project} == *"extension"* ]]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            setDepsVersions ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${CHE_EXTENSIONS_PROPERIES_LIST[@]}
        elif [[ ${project} == *"plugin"* ]]; then
            updateParent ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
            setDepsVersions ${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER} ${CHE_PLUGINS_PROPERIES_LIST[@]}
        fi
        echo ">>>>>>>>>>> DEBUG"
        pushChanesWithMaven . "RELEASE: Set next development version" $1
        cd ../
    done
}

resolveVersions() {
if [[ -z "${RELEASE_VERSION}" ]] || [[ -z "${RELEASE_NEXT_VERSION}" ]] ; then
    echo "RELEASE_VERSION and RELEASE_NEXT_VERSION must be set in ENV"
    exit 1
else
    VERSION=${RELEASE_VERSION}
    NEXT_DEV_VERSION=${RELEASE_NEXT_VERSION}
fi
    echo -e "\x1B[92m############### RELEASE VERSION: ${VERSION}\x1B[0m"
    echo -e "\x1B[92m############### NEXT DEV VERSION: ${NEXT_DEV_VERSION}\x1B[0m"
}

setDepsVersions() {
    local VERSION_OF_DEPS=$1 && shift
    local DEPS_LIST=($@)
    echo -e "\x1B[92m############### Update dependencies versions.\x1B[0m"
    updateDependencies $VERSION_OF_DEPS ${DEPS_LIST[@]}
    pushChanesWithMaven pom.xml "RELEASE: Update dependencies versions" ${RELEASE_BRANCH_NAME}
}

setParentVersion() {
    echo -e "\x1B[92m############### Update parent pom version in $1\x1B[0m"
    updateParent $2
    pushChanesWithMaven pom.xml "RELEASE: Update parent pom version" ${RELEASE_BRANCH_NAME}
}

releaseProject() {
        echo -e "\x1B[92m############### Release: $1\x1B[0m"
        mvn release:prepare release:perform -Dresume=false -Dtag=$2 -DdevelopmentVersion=$3 -DreleaseVersion=$2 "-Darguments=-DskipTests=true -Dskip-validate-sources -Dgpg.passphrase=${GPG_PASSPHRASE} -Darchetype.test.skip=true -Dversion.animal-sniffer.enforcer-rule=1.16"
}

set_tags_in_che_dockerfiles_for_release() {
        THEIA_VERSION="$(awk '/ARG THEIA_VERSION=/{print $NF}' dockerfiles/theia/Dockerfile | cut -d '=' -f2)-$VERSION"
        sed -i -e "s#nightly#$VERSION#" dockerfiles/base/scripts/base/images/images-bootstrap
        sed -i -e "s#nightly#$VERSION#" dockerfiles/base/scripts/base/images/images-utilities
        sed -i -e "s#.*#$VERSION#" dockerfiles/cli/version/latest.ver
        sed -i -e "s#-SNAPSHOT##" dockerfiles/lib/dto-pom.xml
        sed -i -e "s#nightly#$VERSION#" deploy/openshift/deploy_che.sh
        sed -i -e "s#eclipse/che-ip:.*#eclipse/che-ip:$VERSION#" deploy/openshift/ocp.sh
        sed -i -e "s#eclipse/che-theia:.*-nightly#eclipse/che-theia:$THEIA_VERSION#g" ide/che-core-ide-stacks/src/main/resources/stacks.json
        sed -i -e "s#eclipse/che-dev:nightly#eclipse/che-dev:$VERSION#g" ide/che-core-ide-stacks/src/main/resources/stacks.json
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
            setParentVersion ${project} ${VERSION}
            setDepsVersions ${VERSION} ${CHE_PROPERTIES_LIST[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setDepsVersions ${NEXT_DEV_VERSION} ${CHE_PROPERTIES_LIST[@]}
            setParentVersion ${project} ${NEXT_DEV_VERSION}
            mvn clean install -N
        elif [[ ${project} == *"extension"* ]]; then
            setParentVersion ${project} ${VERSION}
            setDepsVersions ${VERSION} ${CHE_EXTENSIONS_PROPERIES_LIST[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setDepsVersions ${NEXT_DEV_VERSION} ${CHE_EXTENSIONS_PROPERIES_LIST[@]}
            setParentVersion ${project} ${NEXT_DEV_VERSION}
        elif [[ ${project} == *"che-plugin"* ]]; then
            setParentVersion ${project} ${VERSION}
            setDepsVersions ${VERSION} ${CHE_PLUGINS_PROPERIES_LIST[@]}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setDepsVersions ${NEXT_DEV_VERSION} ${CHE_PLUGINS_PROPERIES_LIST[@]}
            setParentVersion ${project} ${NEXT_DEV_VERSION}
        else
            setParentVersion ${project} ${VERSION}
            releaseProject ${project} ${VERSION} ${NEXT_DEV_VERSION}
            setParentVersion ${project} ${NEXT_DEV_VERSION}
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
    createBranches ${RELEASE_BRANCH_NAME}
    createBranches set_next_version_in_master_${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
    setNextDevelopmentVersionInMaster set_next_version_in_master_${RELEASE_NEXT_DEVELOPMENT_VERSION_IN_MASTER}
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
che.version
)

CHE_EXTENSIONS_PROPERIES_LIST=(
che.version
)

CHE_PLUGINS_PROPERIES_LIST=(
che.version
)

# KEEP CORRECT ORDER!
#PROJECT_LIST=(
#che-parent
#che-lib
#che-docs
#che
#che-ide-extension
#che-ide-server-extension )

PROJECT_LIST=("${@:3}")
GPG_PASSPHRASE=$2
############################

$1

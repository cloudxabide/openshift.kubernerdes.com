#!/bin/bash

export BASE_DOMAIN=openshift.kubernerdes.com
export CLUSTER_NAME=demo
export REPO_NAME=$BASE_DOMAIN

export ARCH=amd64
export VERSION=stable
export REGION=us-east-1
export PLATFORM=aws

case $ARCH in
  arm64)
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/openshift-release-dev/ocp-release-nightly:4.9.0-0.nightly-arm64-2021-08-16-154214
  ;;
  *)
    export RELEASE_IMAGE=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$VERSION/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
  ;;
esac
echo "RELEASE IMAGE (for $VERSION): $RELEASE_IMAGE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE"

echo "Your Environment will be: $CLUSTER_NAME.$BASE_DOMAIN"

# ~/Developer/OCP4/demo.openshift.kubernerdes.com/2025-01-01-0913
# THEDATE format is YYYY-MM-DD-HHmm
export THEDATE=`date +%F-%H%M`
export OCP4_BASE=${HOME}/Developer/OCP4/ 
export OCP4_DIR=${OCP4_BASE}${CLUSTER_NAME}.${BASE_DOMAIN}/${THEDATE}
export INSTALL_DIR="${OCP4_DIR}/install"
export INSTALLER_DIR="${OCP4_DIR}/installer"

# Create the "base directory" and change to it
mkdir ${OCP4_BASE}; cd $_

# Create all the Directories, if missing
[ ! -d ${OCP4_BASE} ] && { mkdir ${OCP4_BASE}; cd $_; } || { cd ${OCP4_BASE}; }
[ ! -d ${OCP4_DIR} ] && { mkdir -p ${OCP4_DIR}; } 
[ ! -d ${INSTALL_DIR} ] && { mkdir -p ${INSTALL_DIR}; } 
[ ! -d ${INSTALLER_DIR} ] && { mkdir -p ${INSTALLER_DIR}; } 
ln -s ${OCP4_BASE}${CLUSTER_NAME}.${BASE_DOMAIN}/${THEDATE} ${OCP4_BASE}${CLUSTER_NAME}.${BASE_DOMAIN}/latest

# First, identify the files and make sure they are present
### SSH tweaks
SSH_KEY_FILE="${HOME}/.ssh/id_rsa-${CLUSTER_NAME}.${BASE_DOMAIN}"
SSH_KEY_FILE_PUB="${HOME}/.ssh/id_rsa-${CLUSTER_NAME}.${BASE_DOMAIN}.pub"
[ ! -f $SSH_KEY_FILE_PUB ] && { ssh-keygen -tecdsa -b521 -E sha512 -N '' -f $SSH_KEY_FILE; }
SSH_KEY=$(cat $SSH_KEY_FILE_PUB)
eval "$(ssh-agent -s)"
ssh-add ${HOME}/.ssh/id_rsa-${CLUSTER_NAME}.${BASE_DOMAIN}

# Manage Pull Secret
PULL_SECRET_FILE=${OCP4_BASE}pull-secret.txt
[ ! -f $PULL_SECRET_FILE ] && { echo "ERROR: Pull Secret File Not Available. Hit CTRL-C within 10 seconds."; sleep 10; exit 9; }
PULL_SECRET=$(cat $PULL_SECRET_FILE)
export BASE_DOMAIN SSH_KEY PULL_SECRET CLUSTER_NAME AWS_DEFAULT_PROFILE
echo -e "Base Domain: $BASE_DOMAIN \nCluster Name: $CLUSTER_NAME \nAWS Default Profile:  $AWS_DEFAULT_PROFILE \nSSH Key: $SSH_KEY"
echo "Pull Secret is hydrated"

# Download the client and installer
cd $INSTALLER_DIR
[ -e $VERSION ] && VERSION="stable"
case `uname` in
  Linux)
    for FILE in openshift-install-linux.tar.gz openshift-client-linux.tar.gz
    do
      [ ! -f ${FILE} ] && { wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${VERSION}/${FILE}; tar -xvzf ${FILE}; }
    done
  ;;
  Darwin)
    for FILE in openshift-install-mac.tar.gz openshift-client-mac.tar.gz
    do
      [ ! -f ${FILE} ] && { curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${VERSION}/${FILE} -o ${FILE}; tar -xvzf ${FILE}; }
    done
  ;;
esac

cd $OCP4_DIR

## Pull down a generic/vanilla copy of the install-config with no bespoke data - you'll
#   add your own environment variables in a bit)
case $ARCH in
  arm64)
    INSTALL_CONFIG=install-config-${PLATFORM}-${CLUSTER_NAME}.${BASE_DOMAIN}-arm64.yaml
  ;;
  *)
    INSTALL_CONFIG=install-config-${PLATFORM}-${CLUSTER_NAME}.${BASE_DOMAIN}.yaml
  ;;
esac
echo "Installation Configuration: $INSTALL_CONFIG"

[ ! -f $INSTALL_CONFIG ] && { curl -o $INSTALL_CONFIG https://raw.githubusercontent.com/cloudxabide/${REPO_NAME}/main/Files/$INSTALL_CONFIG; echo "You need to update the config file found in this directory"; }

# Using the vanilla config as a base, update the install and deposit it in the "Install Dir"
envsubst < $INSTALL_CONFIG > ${INSTALL_DIR}/install-config.yaml

# Make sure there are no variables that have not been udpated/replaced (or remain "unset")
#  TODO - This doesn't actually work (it just finds End of Line, not un-replaced Variables)
grep \$ ${INSTALL_DIR}/install-config.yaml

#
# $INSTALLER_DIR/openshift-install create help
# $INSTALLER_DIR/openshift-install create install-config --dir=$INSTALL_DIR

# Create the IAM role request
# oc adm release extract quay.io/openshift-release-dev/ocp-release:4.y.z-x86_64 --credentials-requests --cloud=aws
# oc adm release extract quay.io/openshift-release-dev/ocp-release:4.10-latest-x86_64 --credentials-requests --cloud=aws

# Let's roll
LOG_LEVEL=info
MYLOG="${OCP4_DIR}/command_line_install_log.log"
echo "Start: `date`" >> $MYLOG
${INSTALLER_DIR}/openshift-install create manifests --dir=${INSTALL_DIR}/
${INSTALLER_DIR}/openshift-install create cluster --dir=${INSTALL_DIR}/ --log-level=$LOG_LEVEL
echo "End: `date`" >> $MYLOG

cp ${INSTALL_DIR}/auth/kubeconfig ~/.kube/${CLUSTER_NAME}.${BASE_DOMAIN}.kubeconfig
export KUBECONFIG=~/.kube/${CLUSTER_NAME}.${BASE_DOMAIN}.kubeconfig

# ${INSTALLER_DIR}/openshift-install destroy cluster --dir=${INSTALL_DIR}/ --log-level=debug



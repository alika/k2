#!/bin/bash -
#title           :kraken-up.sh
#description     :use docker-machine to bring up a kraken cluster manager instance.
#author          :Samsung SDSRA
#==============================================================================
set -o errexit
set -o nounset
set -o pipefail

# kraken root folder
KRAKEN_ROOT=$(dirname "${BASH_SOURCE}")/..

source "${KRAKEN_ROOT}/cluster/utils.sh"

function setup_dockermachine {
  local dm_command="docker-machine create ${KRAKEN_DOCKER_MACHINE_OPTIONS} ${KRAKEN_DOCKER_MACHINE_NAME}"
  inf "Starting docker-machine with:\n  '${dm_command}'"

  eval ${dm_command}
}


while [[ $# > 1 ]]
do
key="$1"

case $key in
    --clustertype)
    KRAKEN_CLUSTER_TYPE="$2"
    shift 
    ;;
    --dmopts)
    KRAKEN_DOCKER_MACHINE_OPTIONS="$2"
    shift 
    ;;
    --dmname)
    KRAKEN_DOCKER_MACHINE_NAME="$2"
    shift 
    ;;
    *)
      # unknown option
    ;;
esac
shift # past argument or value
done


if [ -z ${KRAKEN_DOCKER_MACHINE_NAME+x} ]; then 
  error "--dmname not specified. Docker Machine name is required."
  exit 1
fi

if [ -z ${KRAKEN_CLUSTER_TYPE+x} ]; then 
  warn "--clustertype not specified. Assuming 'aws'"
  KRAKEN_CLUSTER_TYPE="aws"
fi

if [ ! -f "${KRAKEN_ROOT}/terraform/${KRAKEN_CLUSTER_TYPE}/terraform.tfvars" ]; then 
  error "${KRAKEN_ROOT}/terraform/${KRAKEN_CLUSTER_TYPE}/terraform.tfvars is not present."
  exit 1
fi

if [ ! -f "${KRAKEN_ROOT}/terraform/${KRAKEN_CLUSTER_TYPE}/Dockerfile" ]; then 
  error "${KRAKEN_ROOT}/terraform/${KRAKEN_CLUSTER_TYPE}/Dockerfile is not present."
  exit 1
fi

if docker-machine ls -q | grep --silent "${KRAKEN_DOCKER_MACHINE_NAME}"; then 
  inf "Machine ${KRAKEN_DOCKER_MACHINE_NAME} already exists."
else
  if [ -z ${KRAKEN_DOCKER_MACHINE_OPTIONS+x} ]; then 
    error "--dmopts not specified. Docker Machine option string is required unless machine ${KRAKEN_DOCKER_MACHINE_NAME} already exists."
    exit 1
  fi
  setup_dockermachine
fi

eval "$(docker-machine env ${KRAKEN_DOCKER_MACHINE_NAME})"

# create the data volume container for state
if docker inspect kraken_data &> /dev/null; then
  inf "Data volume container kraken_data already exists."
else
  inf "Creating data volume:\n  'docker create -v /kraken_data --name kraken_data busybox /bin/sh'"
  docker create -v /kraken_data --name kraken_data busybox /bin/sh
fi

# now build the docker container
inf "Building kraken container:\n  'docker build -t samsung_ag/kraken -f \"${KRAKEN_ROOT}/terraform/${KRAKEN_CLUSTER_TYPE}/Dockerfile\" \"${KRAKEN_ROOT}\"'"
docker build -t samsung_ag/kraken -f "${KRAKEN_ROOT}/terraform/${KRAKEN_CLUSTER_TYPE}/Dockerfile" "${KRAKEN_ROOT}"

# run cluster up
inf "Building kraken cluster:\n  'docker run --volumes-from kraken_data samsung_ag/kraken terraform apply -input=false -state=/kraken_data/terraform.tfstate -var-file=/opt/kraken/terraform/aws/terraform.tfvars /opt/kraken/terraform/aws'"
docker run -d --name kraken_cluster --volumes-from kraken_data samsung_ag/kraken terraform apply -input=false -state=/kraken_data/terraform.tfstate -var-file=/opt/kraken/terraform/aws/terraform.tfvars /opt/kraken/terraform/aws 

inf "Following docker logs now. Ctrl-C to cancel."
docker logs --follow kraken_cluster



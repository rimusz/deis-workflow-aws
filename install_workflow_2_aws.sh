#!/bin/bash

set_settings() {
# check for settings file
if [[ ! -f settings ]]
then
  echo "'settings' file is missing!!!"
  echo "Rename/copy 'settings.tpl' file to 'settings', then set S3 region, and AWS keys there"
  exit 0
fi

# Overall Workflow settings
# S3 region
# AWS credentials
source settings
}


install() {
  # get seeitngs
  set_settings

  # get k8s cluster name
  cluster

  # get lastest macOS helmc cli version
  install_helmc

  # get lastest macOS deis cli version
  install_deis

  # add Deis Chart repo
  echo "Adding Deis Chart repository ... "
  helmc repo add deis https://github.com/deis/charts
  # get the latest version of all Charts from all repos
  echo " "
  echo "Get the latest version of all Charts from all repos ... "
  helmc up

  # get latest Workflow version
  echo " "
  echo "Getting latest Deis Workflow version ..."
  WORKFLOW_RELEASE=$(ls ~/.helmc/cache/deis | grep workflow-v2. | grep -v -e2e | sort -rn | head -1 | cut -d'-' -f2)
  echo "Got Deis Workflow ${WORKFLOW_RELEASE} ..."

  # delete the old folder if such exists
  rm -rf ~/.helmc/workspace/charts/workflow-${WORKFLOW_RELEASE}-${K8S_NAME} > /dev/null 2>&1

  # fetch Deis Workflow Chart to your helmc's working directory
  echo " "
  echo "Fetching Deis Workflow Chart to your helmc's working directory ..."
  helmc fetch deis/workflow-${WORKFLOW_RELEASE} workflow-${WORKFLOW_RELEASE}-${K8S_NAME}

  ####
  # set env vars
  # so we do not have to edit generate_params.toml in chart’s tpl folder
  # set storage to AWS S3
  STORAGE_TYPE=s3
  S3_REGION=${BUCKETS_S3_REGION}
  AWS_ACCESS_KEY=${AWS_ACCESS_KEY_ID}
  AWS_SECRET_KEY=${AWS_SECRET_ACCESS_KEY}
  AWS_REGISTRY_BUCKET=${K8S_NAME}-deis-registry
  AWS_DATABASE_BUCKET=${K8S_NAME}-deis-database
  AWS_BUILDER_BUCKET=${K8S_NAME}-deis-builder

  # set off-cluster registry
  REGISTRY_LOCATION=ecr
  ECR_REGION=${BUCKETS_S3_REGION}
  ECR_ACCESS_KEY=${AWS_ACCESS_KEY_ID}
  ECR_SECRET_KEY=${AWS_SECRET_ACCESS_KEY}

  # export as env vars
  export STORAGE_TYPE S3_REGION AWS_ACCESS_KEY AWS_SECRET_KEY AWS_REGISTRY_BUCKET AWS_DATABASE_BUCKET AWS_BUILDER_BUCKET REGISTRY_LOCATION ECR_ACCESS_KEY ECR_SECRET_KEY ECR_REGION
  ####

  # set off-cluster Postgres
  set_database

  # generate manifests
  echo " "
  echo "Generating Workflow ${WORKFLOW_RELEASE}-${K8S_NAME} manifests ..."
  helmc generate -x manifests -f workflow-${WORKFLOW_RELEASE}-${K8S_NAME}

  # set intenal AWS LB - WIP
  if [[ ! -z "$ILB" ]]
  then
    echo "Enabling internal LoadBalancer for Workflow Router ..."
  fi

  # install Workflow
  echo " "
  echo "Installing Workflow ..."
  helmc install workflow-${WORKFLOW_RELEASE}-${K8S_NAME}

  # Waiting for Deis Workflow to be ready
  wait_for_workflow
  #

  # get router's external IP
  echo " "
  echo "Fetching Router's LB IP:"
  LB_IP=$(kubectl --namespace=deis get svc | grep [d]eis-router | awk '{ print $3 }')
  echo "$LB_IP"

  echo " "
  echo "Workflow install ${WORKFLOW_RELEASE} is done ..."
  echo " "
}

upgrade() {
  # get seeitngs
  set_settings

  # get k8s cluster name
  cluster

  # get lastest macOS helmc cli version
  install_helmc

  # get lastest macOS deis cli version
  install_deis

  # get the latest version of all Charts from all repos
  echo " "
  echo "Get the latest version of all Charts from all repos ... "
  helmc up
  echo " "

  # Fetch the current database credentials
  echo " "
  echo "Fetching the current database credentials ..."
  kubectl --namespace=deis get secret database-creds -o yaml > ~/tmp/active-deis-database-secret-creds.yaml

  # Fetch the builder component ssh keys
  echo " "
  echo "Fetching the builder component ssh keys ..."
  kubectl --namespace=deis get secret builder-ssh-private-keys -o yaml > ~/tmp/active-deis-builder-secret-ssh-private-keys.yaml

  # export environment variables for the previous and latest Workflow versions
  export PREVIOUS_WORKFLOW_RELEASE=$(cat ~/tmp/active-deis-builder-secret-ssh-private-keys.yaml | grep chart.helm.sh/version: | awk '{ print $2 }')
  export DESIRED_WORKFLOW_RELEASE=$(ls ~/.helmc/cache/deis | grep workflow-v2. | grep -v -e2e | sort -rn | head -1 | cut -d'-' -f2)

  # delete the old chart folder if such exists
  rm -rf ~/.helmc/workspace/charts/workflow-${DESIRED_WORKFLOW_RELEASE}-${K8S_NAME} > /dev/null 2>&1

  # Fetching the new chart copy from the chart cache into the helmc workspace for customization
  echo " "
  echo "Fetching Deis Workflow Chart to your helmc's working directory ..."
  helmc fetch deis/workflow-${DESIRED_WORKFLOW_RELEASE} workflow-${DESIRED_WORKFLOW_RELEASE}-${K8S_NAME}

  ####
  # set env vars
  # so we do not have to edit generate_params.toml in chart’s tpl folder
  # set storage to AWS S3
  STORAGE_TYPE=s3
  S3_REGION=${BUCKETS_S3_REGION}
  AWS_ACCESS_KEY=${AWS_ACCESS_KEY_ID}
  AWS_SECRET_KEY=${AWS_SECRET_ACCESS_KEY}
  AWS_REGISTRY_BUCKET=${K8S_NAME}-deis-registry
  AWS_DATABASE_BUCKET=${K8S_NAME}-deis-database
  AWS_BUILDER_BUCKET=${K8S_NAME}-deis-builder

  # set off-cluster registry
  REGISTRY_LOCATION=ecr
  ECR_REGION=${BUCKETS_S3_REGION}
  ECR_ACCESS_KEY=${AWS_ACCESS_KEY_ID}
  ECR_SECRET_KEY=${AWS_SECRET_ACCESS_KEY}

  # export as env vars
  export STORAGE_TYPE S3_REGION AWS_ACCESS_KEY AWS_SECRET_KEY AWS_REGISTRY_BUCKET AWS_DATABASE_BUCKET AWS_BUILDER_BUCKET REGISTRY_LOCATION ECR_ACCESS_KEY ECR_SECRET_KEY ECR_REGION
  ####

  # set off-cluster Postgres
  set_database

  # Generate templates for the new release
  echo " "
  echo "Generating Workflow ${DESIRED_WORKFLOW_RELEASE}-${K8S_NAME} manifests ..."
  helmc generate -x manifests workflow-${DESIRED_WORKFLOW_RELEASE}-${K8S_NAME}

  # Copy your active database secrets into the helmc workspace for the desired version
  cp -f ~/tmp/active-deis-database-secret-creds.yaml \
    $(helmc home)/workspace/charts/workflow-${DESIRED_WORKFLOW_RELEASE}-${K8S_NAME}/manifests/deis-database-secret-creds.yaml

  # Copy your active builder ssh keys into the helmc workspace for the desired version
  cp -f ~/tmp/active-deis-builder-secret-ssh-private-keys.yaml \
    $(helmc home)/workspace/charts/workflow-${DESIRED_WORKFLOW_RELEASE}-${K8S_NAME}/manifests/deis-builder-secret-ssh-private-keys.yaml

  # Uninstall Workflow
  echo " "
  echo "Uninstalling Workflow ${PREVIOUS_WORKFLOW_RELEASE} ... "
  helmc uninstall workflow-${PREVIOUS_WORKFLOW_RELEASE}-${K8S_NAME} -n deis

  sleep 3

  # Install of latest Workflow release
  echo " "
  echo "Installing Workflow ${DESIRED_WORKFLOW_RELEASE} ... "
  helmc install workflow-${DESIRED_WORKFLOW_RELEASE}-${K8S_NAME}

  # Waiting for Deis Workflow to be ready
  wait_for_workflow

  echo " "
  echo "Workflow upgrade to ${DESIRED_WORKFLOW_RELEASE} is done ..."
  echo " "

}

set_database() {
if [[ ! -f postgres_settings ]]
then
  echo " "
  echo "No postgres_settings file found !!! "
  echo "PostgreSQL database will be set to on-cluster ..."
else
  echo " "
  echo "postgres_settings file found !!!"
  echo "PostgreSQL database will be set to off-cluster ..."
  DATABASE_LOCATION="off-cluster"
  # import values from file
  source postgres_settings
  # export values as environment variables
  export DATABASE_LOCATION DATABASE_HOST DATABASE_PORT DATABASE_NAME DATABASE_USERNAME DATABASE_PASSWORD
fi
}

cluster() {
  # get k8s cluster name
  echo " "
  echo "Fetching Kubernetes cluster name ..."
  K8S_NAME=$(kubectl config current-context | cut -c 5-)
  echo "Kubernetes cluster name is ${K8S_NAME} ..."
  echo " "
}

install_deis() {
  # get lastest macOS deis cli version
  echo "Downloading latest version of Workflow deis cli ..."
  curl -sSL http://deis.io/deis-cli/install-v2.sh | bash
  mv -f deis ~/bin/
  chmod +x ~/bin/deis
  echo " "
  echo "Installed deis cli to ~/bin ..."
  echo " "
}

install_helmc() {
  # get lastest macOS helmc cli version
  echo "Downloading latest version of helmc cli ..."
  curl -o ~/bin/helmc https://storage.googleapis.com/helm-classic/helmc-latest-darwin-amd64
  chmod +x ~/bin/helmc
  echo " "
  echo "Installed helmc cli to ~/bin ..."
  echo " "
}

install_helm() {
  # get lastest macOS helm cli version
  echo " "
  echo "Checking for latest Helm version..."
  mkdir ~/tmp > /dev/null 2>&1
  LATEST_HELM=$(curl -s https://api.github.com/repos/kubernetes/helm/releases/latest | grep "tag_name" | awk '{print $2}' | sed -e 's/"\(.*\)"./\1/')

  # check if the binary exists
  if [ ! -f ~/bin/helm ]; then
      INSTALLED_HELM=v0.0.0
  else
      INSTALLED_HELM=$(~/bin/helm version)
  fi
  #
  MATCH=$(echo "${INSTALLED_HELM}" | grep -c "${LATEST_HELM}")
  if [ $MATCH -ne 0 ]; then
      echo " "
      echo "Helm is up to date !!!"
  else
      echo " "
      echo "Downloading latest ${LATEST_HELM} of 'helm' cli for macOS"
      curl -k -L http://storage.googleapis.com/kubernetes-helm/helm-${LATEST_HELM}-darwin-amd64.tar.gz > ~/tmp/helm.tar.gz
      tar xvf ~/tmp/helm.tar.gz -C ~/tmp --strip=1 darwin-amd64/helm > /dev/null 2>&1
      chmod +x ~/tmp/helm
      mv -f ~/tmp/helm ~/bin/helm
      rm -f ~/tmp/helm.tar.gz
      echo " "
      echo "Installed latest ${LATEST_HELM} of 'helm' cli to ~/bin ..."
      echo " "
      echo "Installing new version of Helm Tiller..."
      kubectl --namespace=kube-system delete deployment tiller-deploy > /dev/null 2>&1
      ~/bin/helm init
      echo "Helm is ready to sail ..."
  fi
}

wait_for_workflow() {
  echo " "
  echo "Waiting for Deis Workflow to be ready... but first, coffee! "
  spin='-\|/'
  i=1
  until kubectl --namespace=deis get po | grep [d]eis-builder- | grep "1/1"  >/dev/null 2>&1; do i=$(( (i+1) %4 )); printf "\r${spin:$i:1}"; sleep .1; done
  until kubectl --namespace=deis get po | grep [d]eis-registry- | grep "1/1"  >/dev/null 2>&1; do i=$(( (i+1) %4 )); printf "\r${spin:$i:1}"; sleep .1; done
  if [[ ! -f postgres_settings ]]
  then
    until kubectl --namespace=deis get po | grep [d]eis-database- | grep "1/1"  >/dev/null 2>&1; do i=$(( (i+1) %4 )); printf "\r${spin:$i:1}"; sleep .1; done
  fi
  until kubectl --namespace=deis get po | grep [d]eis-router- | grep "1/1"  >/dev/null 2>&1; do i=$(( (i+1) %4 )); printf "\r${spin:$i:1}"; sleep .1; done
  until kubectl --namespace=deis get po | grep [d]eis-controller- | grep "1/1"  >/dev/null 2>&1; do i=$(( (i+1) %4 )); printf "\r${spin:$i:1}"; sleep .1; done
  echo " "
}

usage() {
    echo "Usage: install_workflow_2_aws.sh install | upgrade | deis | helmc | helm | cluster"
}

case "$1" in
        install)
                install
                ;;
        upgrade)
                upgrade
                ;;
        deis)
                install_deis
                ;;
        helmc)
                install_helmc
                ;;
        helm)
                install_helm
                ;;
        cluster)
                cluster
                ;;
        *)
                usage
                ;;
esac

#!/usr/bin/env bash
#set -o errexit
#set -x
set -o nounset

__DIR__="$(cd "$(dirname "${0}")"; echo $(pwd))"
__BASE__="$(basename "${0}")"
__FILE__="${__DIR__}/${__BASE__}"

update_os() {
  echo
  echo "Updating OS"
  echo "------------------------------------"
  echo
  apt-get update -q
  apt-get upgrade -yq
  #apt-get dist-upgrade -yq
  apt-get autoclean -yq
  service docker status 2> /dev/null | service docker start
  echo "------------------------------------"
  echo
}

run_update_scripts() {
  local lastUpDir=/root/rblastupdate
  if [ ! -d $lastUpDir ];then
    mkdir $lastUpDir
  fi
  local lastUpFile="$lastUpDir/update_scripts"
  local lastUpNr=0
  if [ -f $lastUpFile ];then
    lastUpNr=$(cat $lastUpFile)
  fi
  lastUpNr=$(($lastUpNr + 1))
  while [ -f "${RBLIB}/updates/update_$lastUpNr.sh" ]; do
    echo "Running ${RBLIB}/updates/update_$lastUpNr.sh"
    bash "${RBLIB}/updates/update_$lastUpNr.sh"
    echo $lastUpNr > $lastUpFile
    lastUpNr=$(($lastUpNr + 1))
  done

}

update_self() {
  if [ ! -d "${VAGRANTDOCKER}/.git" ];then
    echo
    echo "Installing vagrant-docker as git repository"
    echo "------------------------------------"
    echo
    # set up a trap to delete the temp dir when the script exits
    unset temp_dir
    trap '[[ -d "$temp_dir" ]] && rm -rf "$temp_dir"' EXIT
    # create the temp dir
    declare -r temp_dir=$(mktemp -dt dockerfiles.XXXXXX)
    git clone https://github.com/reinblau/vagrant-docker.git "${temp_dir}"
    mv "${temp_dir}/.git" "${VAGRANTDOCKER}/.git"
    touch "${VAGRANTDOCKER}/.autocreated"
  elif [ -f "${VAGRANTDOCKER}/.autocreated" ] ;then
    echo
    echo "Self-update of vagrant-docker"
    echo "------------------------------------"
    cd ${VAGRANTDOCKER} && git pull
    run_update_scripts
    echo
    echo "Start update"
    echo "------------------------------------"
    main --noself
  fi
}

update_crane() {
  echo
  echo "Checking version of crane"
  echo "------------------------------------"
  local current_version=$(crane version)
  if [ "${current_version}" != "v${CRANEVERSION}" ];then
    echo "Remove current version (${current_version}) of crane"
    echo "------------------------------------"
    echo
    rm /usr/local/bin/crane 2> /dev/null || true
    source $RBLIB/provision.sh
    crane_install
  else
    echo "Found ${current_version} of crane"
    echo "------------------------------------"
    echo
  fi
}

update_dockerfiles() {
  local subdirs="$DOCKERFILES/*/"
  local gitdir=""
  for dir in ${subdirs}
    do
      gitdir="${dir}.git/"
      local dir_basename="$(echo "$(basename ${dir})")"
      if [[ -f $BLACKLIST ]] && grep ${dir_basename} $BLACKLIST > /dev/null ;then
        continue
      fi

      if [[ -d $gitdir ]];then
        echo
        echo "Updating ${dir}"
        echo "------------------------------------"
        echo
        cd "${dir}"
        su vagrant -c "git pull"
        echo "------------------------------------"
        echo
      fi
  done
}

update_dockerimages() {
  local projects=""
  echo "Kill all containers"
  docker rm -f $(docker ps -aq) 2>/dev/null

  echo "Update built-in images"
  docker pull jwilder/nginx-proxy:0.3.0
  docker pull reinblau/cmd
  echo "------------------------------------"
  echo
  subdirs="$DOCKERFILES/*/"
  for dir in ${subdirs}
  do
    updatefile="${dir}update.sh"
    if [ -f "${updatefile}" ];then
      echo "Executing ${updatefile}"
      bash "${updatefile}"
      echo "------------------------------------"
      echo
    fi
  done

  if [[ -f $PROJECTLIST ]];then
    for project in $(cat "$PROJECTLIST")
      do
      if [[ -f $BLACKLIST ]] && grep ${project} $BLACKLIST >/dev/null ;then
        continue
      fi
      projects="$DOCKERFILES/*/$project/"
      for project_dir in ${projects}
        do
          if [[ -f "$project_dir/crane.yml" ]];then
            echo
            echo "Updating docker image for ${project}"
            echo "------------------------------------"
            echo
            cd $project_dir && crane provision
            echo "------------------------------------"
            echo
          fi
          if [[ -f "$project_dir/update.sh" ]];then
            echo
            echo "Executing extra update for ${project}"
            echo "------------------------------------"
            echo
            bash "$project_dir/update.sh"
            echo "------------------------------------"
            echo
          fi
      done
    done
  fi
}

update_run () {
  local component=$1
  local updatetype=${2:-""}
  local lastUpDir=/root/rblastupdate/
  if [[ ! -d $lastUpDir ]];then
    mkdir $lastUpDir
  fi
  local lastUpFile="$lastUpDir${component}"
  local lastUpTime=0
  local now=$(date +"%s")

  if [ ! -f "${lastUpFile}" ];then
    lastUpTime="${now}"
    echo "${lastUpTime}" > "${lastUpFile}"
  else
    lastUpTime=$(cat "${lastUpFile}")
  fi
  local duration="60 * 60 * 24 * 7"
  local next=$((${lastUpTime} + ${duration}));
  # 7 days are gone or rbupdate cmd or first run
  if [ "${next}" -le "${now}" ] || [ $updatetype == "--updatebyhand" ] || [ $lastUpTime == 0 ];then
    echo "${now}" > "${lastUpFile}"
    update_"${component}"
  fi
}

main () {
  local context=$1
  if [ $context != "--noself" ];then
    update_run "self" "$@"
  fi
  if [ $context == "--noself" ];then
    context="--updatebyhand"
  fi
  update_run "os" "$context"
  update_run "crane" "$context"
  update_run "dockerfiles" "$context"
  update_run "dockerimages" "$context"
  echo
  echo "Starting provisioner"
  echo "------------------------------------"
  echo
  exec "${RBLIB}/start.sh"
}

main "$@"

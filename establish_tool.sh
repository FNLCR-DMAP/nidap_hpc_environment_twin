#!/bin/bash

declare -a repo_urls=(
  "https://github.com/NIDAP-Community/SCWorkflow.git"
  "https://github.com/NIDAP-Community/DSPWorkflow.git"
  "https://github.com/FNLCR-DMAP/SCSAWorkflow.git"
)

declare -a conda_envs=(
  "SC_environment.yml"
  "DSP_environment.yml"
  "SCSA_environment.yml"
)

declare -a conda_pkg_names=(
  "r-scworkflow"
  "r-dspworkflow"
  "spac"
)

UPDATE_VERSIONS="TRUE"

CONDA_BRANCH="Conda_Package"

CONDA_STARTUP="/rstudio-files/ccbr-data/users/RH/Own_Conda/rh_conda/etc/profile.d/conda.sh"

##############################################################
##############################################################
##############################################################
echo "Filesystem Check Now..."

# Format the date and time for the log filename
datetime=$(date "+%Y-%m-%d_%H-%M")
log_file="NIDAP_HPC_ENV_Deployment_${datetime}.log"
RUN_LOG_FOLDER="maintenance_log"

# Get the script's directory
script_dir=$(dirname "$(readlink -f "$0")")
pkg_dir="$script_dir/local_channel/linux-64"
conda_env_dir="$script_dir/conda_env_files"
WORKFLOW_PKG_DIR="$script_dir/workflow_packages"
WORKFLOW_ENV_DIR="$script_dir/workflow_envs"
MAINTENANCE_LOG_DIR="$script_dir/$RUN_LOG_FOLDER"

if [ ! -d "$WORKFLOW_PKG_DIR" ]; then
  mkdir "$WORKFLOW_PKG_DIR"
fi

if [ ! -d "$WORKFLOW_ENV_DIR" ]; then
  mkdir "$WORKFLOW_ENV_DIR"
fi

if [ ! -d "$MAINTENANCE_LOG_DIR" ]; then
  mkdir "$MAINTENANCE_LOG_DIR"
fi


echo "################################################"
echo "################################################"
echo "################################################"

# Start of the script's operations, redirecting all output to the log file
log_file="${MAINTENANCE_LOG_DIR}/NIDAP_HPC_ENV_Deployment_${datetime}.log"
echo $log_file
exec > >(tee "${log_file}") 2>&1

# Preping Conda Environment
# Check if Conda base environment is activated
if [ "$CONDA_DEFAULT_ENV" != "base" ]; then
  echo "Activating Conda base environment..."
  source "$CONDA_STARTUP"
  conda activate base
  echo "Conda base environment activated."
  echo "$(conda --version)"
else
  echo "Conda base environment is already activated."
fi

# Changing environment locations
conda config --prepend envs_dirs $WORKFLOW_ENV_DIR

echo "################################################"
echo "################################################"
echo "################################################"




# Function to extract repository name from URL
get_repo_name() {
  local url="$1"
  local repo_name
  repo_name=$(basename "$url" .git)
  echo "$repo_name"
}

# Function to update environment YAML file
update_env_yaml() {
  local repo_dir="$1"
  local base_env_file="$2"
  local conda_pkg_name="$3"

  # Extract the latest version of $conda_pkg_name
  local version=$(ls $repo_dir | grep "${conda_pkg_name}-[0-9]" | grep -v 'dev' | sort -V | tail -n 1 | sed -n "s/${conda_pkg_name}-\([0-9\.]*\).*/\1/p")
  local new_env_name="${repo_name}_NIDAP_v${version//./_}"
  local new_env_file="${base_env_file%.*}_v${version//./_}.yml"
  
  if [ -f "$conda_env_dir/$new_env_file" ]; then
    echo "Environment file for lated conda version $new_env_file already exists"
    
  else

    # Copy and rename the base YAML file
    cp "$conda_env_dir/$base_env_file" "$conda_env_dir/$new_env_file"
  
    # Update the environment name within the YAML file
    sed -i "s/name: .*/name: $new_env_name/" "$conda_env_dir/$new_env_file"
  
    # Append the r-dspworkflow version at the end of the YAML file
    # echo "  - $conda_pkg_name==$version" >> "$conda_env_dir/$new_env_file"
  
    # Insert the $conda_pkg_name version right below the dependencies section
    awk -v conda_pkg="$conda_pkg_name==$version" '/dependencies:/{print;print "  -",conda_pkg;next}1' "$conda_env_dir/$new_env_file" > "$conda_env_dir/tmp_$new_env_file" && mv "$conda_env_dir/tmp_$new_env_file" "$conda_env_dir/$new_env_file"
  
    echo "Updated environment YAML file: $new_env_file with $new_env_name"
  fi
}

# Loop through the repository URLs
for idx in "${!repo_urls[@]}"; do
  url="${repo_urls[$idx]}"
  repo_name=$(get_repo_name "$url")
  repo_dir="$WORKFLOW_PKG_DIR/$repo_name"
  
  # Check if the directory exists for the repository
  if [ ! -d "$repo_dir" ]; then
    # Directory does not exist, so perform git clone
    git clone -b "$CONDA_BRANCH" "$url" "$repo_dir"
  else
    # Directory exists, so navigate into it and perform git pull
    cd "$repo_dir"
    git pull origin "$CONDA_BRANCH"
    cp ./*.tar.bz2 $pkg_dir
    echo "$repo_name Conda Package Updated in Local Channel."
    cd -
  fi
  echo "################################################"
  
  if [ "$UPDATE_VERSIONS" = "TRUE" ]; then
    echo "Updating versions for $repo_name..."
    # Update environment YAML file
    update_env_yaml "$repo_dir" "${conda_envs[$idx]}" "${conda_pkg_names[$idx]}"
  else
    echo "Skipping version updates for $repo_name..."
  fi
  
  echo "################################################"
done

echo "################################################"
echo "################################################"

echo "Update local_channel index"
conda index $script_dir/local_channel/ --channel-name local_channel
conda config --set show_channel_urls yes
LOCAL_CHANNEL_PATH="file://$script_dir/local_channel/"
conda config --add channels "$LOCAL_CHANNEL_PATH"

echo "################################################"
echo "################################################"
echo "################################################"


echo "Updating Workflow Environments."

for env_path in "$conda_env_dir"/*.yml; do
  # Extract the filename from the path
  env_file=$(basename "$env_path")
  # Extract the environment name from the .yml file
  current_env="$(grep "name:" "$env_path" | cut -d ':' -f 2 | awk '{$1=$1};1')"

  # Check if the Conda environment already exists
  if conda env list | grep -q "^$current_env\s"; then
    echo "Environment $current_env already exists."
    echo "################################################"
    echo "################################################"
  else
    echo "Environment $current_env does not exist. Creating..."
    sed -i '/^ *- file:\/\//d' "$env_path"
    
    sed -i "/channels:/a \  - $LOCAL_CHANNEL_PATH" "$env_path"
    
    echo "Local channels updated in $env_path."
    echo "Creating $current_env Now..."
    
    # Ensure you replace '/path/to/env/directory' with the actual path where the environment should be created
    # The -n "$current_env" might be redundant when using --prefix, ensure to adjust based on your requirement
    conda env create -v -f "$env_path"
    
    if [ $? -ne 0 ]; then
      echo "Failed to create Conda environment: $current_env"
      # Handle the failure case, e.g., exit or continue with additional steps
      echo "################################################"
      echo "################################################"
      continue  # Skip to the next iteration of the loop
    else
      echo "Successfully created Conda environment: $current_env"
    fi
    
    echo "################################################"
    echo "################################################"
  fi
done

echo "################################################"
echo "################################################"
echo "################################################"
echo "Listing all Conda environments:"
conda env list


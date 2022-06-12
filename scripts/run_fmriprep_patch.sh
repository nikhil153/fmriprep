#!/bin/bash

# Author: nikhil153
# Date: 16 Feb 2022

# Example command:
# test_script.sh -b ~/scratch/test_data/bids \
#                -w ~/scratch/test_data/tmp \
#                -s 001
#                -f ~/scratch/my_repos/fmriprep/fmriprep
#                -c ~/scratch/my_containers/fmriprep_codecarbon_v2.1.2.sif
#                -g "CAN"
#                -t ~/scratch/templateflow

if [ "$#" -lt 12 ]; then
  echo "Incorrect number of arguments: $#. Please provide paths to following:"
  echo "  BIDS dir (-b): input for fmriprep"
  echo "  working dir (-w): directory for fmriprep processing"
  echo "  subject ID (-s): subject subdirectory inside BIDS_DIR"
  echo "  fmriprep code dir (-f): directory for local fmriprep code (carbon-trackers branch)"
  echo "  container (-c): singularity container with carbon tracker packages and dependencies"
  echo "  geolocation (-g): country code used by CodeCarbon to estimate emissions e.g. CAN"
  echo "  templateflow (-t): templateflow dir (optional)"
  echo ""
  echo "Note: the freesurfer license.txt must be inside the working_dir"
  exit 1
fi

while getopts b:w:s:f:c:g:t: flag
do
    case "${flag}" in
        b) BIDS_DIR=${OPTARG};;
        w) WD_DIR=${OPTARG};;
        s) SUB_ID=${OPTARG};;
        f) FMRIPREP_CODE=${OPTARG};;
        c) CON_IMG=${OPTARG};;
        g) COUNTRY_CODE=${OPTARG};;
        t) TEMPLATEFLOW_DIR=${OPTARG};;        
    esac
done

echo ""
echo "Checking arguments provided..."
echo ""

if [ ! -z $TEMPLATEFLOW_DIR ] 
then 
    echo "Using templates from local templateflow dir: $TEMPLATEFLOW_DIR"
else
    echo "Local templateflow dir not specified. Templates will be downloaded..."
    TEMPLATEFLOW_DIR="Not provided"
fi

echo "
      BIDS dir: $BIDS_DIR 
      working dir: $WD_DIR
      subject id: $SUB_ID
      fmriprep code dir: $FMRIPREP_CODE
      container: $CON_IMG
      templateflow: $TEMPLATEFLOW_DIR
      geolocation: $COUNTRY_CODE
      "

DERIVS_DIR=${WD_DIR}/output

LOG_FILE=${WD_DIR}_fmriprep_anat.log
echo "Starting fmriprep proc with container: ${CON_IMG}"
echo ""

# Create subject specific dirs
FMRIPREP_HOME=${DERIVS_DIR}/fmriprep_home_${SUB_ID}
echo "Processing: ${SUB_ID} with home dir: ${FMRIPREP_HOME}"
echo ""
mkdir -p ${FMRIPREP_HOME}

LOCAL_FREESURFER_DIR="${DERIVS_DIR}/freesurfer-6.0.1"
mkdir -p ${LOCAL_FREESURFER_DIR}

# Prepare some writeable bind-mount points.
FMRIPREP_HOST_CACHE=$FMRIPREP_HOME/.cache/fmriprep
mkdir -p ${FMRIPREP_HOST_CACHE}

# Make sure FS_LICENSE is defined in the container.
mkdir -p $FMRIPREP_HOME/.freesurfer
export SINGULARITYENV_FS_LICENSE=$FMRIPREP_HOME/.freesurfer/license.txt
cp ${WD_DIR}/license.txt ${SINGULARITYENV_FS_LICENSE}

# Designate a templateflow bind-mount point
export SINGULARITYENV_TEMPLATEFLOW_DIR="/templateflow"

# Singularity CMD 
if [[ $TEMPLATEFLOW_DIR == "Not provided" ]]; then
  SINGULARITY_CMD="singularity run \
  -B ${BIDS_DIR}:/data_dir \
  -B ${FMRIPREP_CODE}:/usr/local/miniconda/lib/python3.7/site-packages/fmriprep:ro \
  -B ${FMRIPREP_HOME}:/home/fmriprep --home /home/fmriprep --cleanenv \
  -B ${DERIVS_DIR}:/output \
  -B ${WD_DIR}:/work \
  -B ${LOCAL_FREESURFER_DIR}:/fsdir \
  ${CON_IMG}"
else
  SINGULARITY_CMD="singularity run \
  -B ${BIDS_DIR}:/data_dir \
  -B ${FMRIPREP_CODE}:/usr/local/miniconda/lib/python3.7/site-packages/fmriprep:ro \
  -B ${FMRIPREP_HOME}:/home/fmriprep --home /home/fmriprep --cleanenv \
  -B ${DERIVS_DIR}:/output \
  -B ${TEMPLATEFLOW_DIR}:${SINGULARITYENV_TEMPLATEFLOW_DIR} \
  -B ${WD_DIR}:/work \
  -B ${LOCAL_FREESURFER_DIR}:/fsdir \
  ${CON_IMG}"
fi

# Remove IsRunning files from FreeSurfer
find ${LOCAL_FREESURFER_DIR}/sub-$SUB_ID/ -name "*IsRunning*" -type f -delete

# Compose the command line
cmd="${SINGULARITY_CMD} /data_dir /output participant --participant-label $SUB_ID \
-w /work --output-spaces MNI152NLin2009cAsym:res-2 anat fsnative fsaverage5 \
--fs-subjects-dir /fsdir \
--anat-only \
--skip_bids_validation \
--fs-license-file /home/fmriprep/.freesurfer/license.txt \
--return-all-components -v \
--write-graph --track-carbon --country-code $COUNTRY_CODE --notrack"

# Optional cmds
#--bids-filter-file ${BIDS_FILTER} --anat-only 

# Setup done, run the command
unset PYTHONPATH
echo Commandline: $cmd
eval $cmd
exitcode=$?

exit $exitcode

echo "fmriprep run completed!"

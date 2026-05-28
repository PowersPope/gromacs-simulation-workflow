#!/bin/bash -l
#SBATCH --account=parisahlab
#SBATCH --partition=gpulong
#SBATCH --time=12:00:00
#SBATCH --gpus=1
#SBATCH --cpus-per-gpu=16
#SBATCH --mem-per-gpu=32G
#SBATCH --job-name=gromacs-replicate
#SBATCH --output=slurmout/gromacs-additional-timesteps-%j.out
#SBATCH --mail-user=apowers4@uoregon.edu
#SBATCH --mail-type=END,FAIL   # When to send the emails


### Help
if [ "$1" == "-h" ]; then
  echo "Make sure to run this in the directory that you want to continue. As there will be no supplied arguments!"
  echo "Required arguments:"
  echo "  <dir_name>      : Name of the directory with which a MD run using gromacs was already run and setup."
  echo "  <replicate>     : The replicate number to add to all of our outputs."
  exit 0
fi

# Parse arguments
run_dir=$1
replicate=$2

# Initialize variables
production_mdp="md.mdp"

# Check to see if our directory exists if not then error and exit, cd to if it does.
if [ ! -d "$run_dir" ]; then
      echo "Error: Run directory '$run_dir' does not exist. Cannot resume."
      exit 1
fi
cd "$run_dir" || exit 1

# Print info about GPU allocation.
echo "Allocated GPU(s): $CUDA_VISIBLE_DEVICES"
echo "GPU details:"
nvidia-smi --query-gpu=index,name,driver_version --format=csv,noheader

### In this section I'm tweaking between loading the slurm default gromacs
### or a more recent docker image using singularity.

module load gromacs/2024.3-plumed-2.11.0-cuda-12.4.1

# Switched to using docker image of more recent gromacs version, due to old version
# only seemingly being able to do one restraint at a time.
# mpirun used instead of srun to avoid compatibility issues with the mpi

# shopt -s expand_aliases
# alias gmx='mpirun singularity exec --nv ../gromacs_latest.sif gmx'

###

export OMP_NUM_THREADS=16

# Specify the force field folder as working directory.
export GMXLIB
GMXLIB=$(pwd)

# Production Continuation
run_production() {
  if [ -f "md_0_1.gro" ]; then
    echo "Topology .gro file found."
  else
    echo "Topology .gro file not found! Make sure that $run_dir has already been equilibrated and run before!"
    exit 1
  fi
  echo "Creating a new md trajectory replicate with number $replicate"

  gmx grompp -f "$production_mdp" -c npt.gro -t npt.cpt -p topol.top -o md_0_1.tpr
  # Execute production run
  echo "Executing production run. See readout at $run_dir/md_0_1_${replicate}_error.log"
  gmx mdrun -deffnm md_0_1_${replicate} \
            -s md_0_1.tpr \
            -v -stepout 10000 2> md_0_1_${replicate}_error.log

  if [ $? -ne 0 ]; then # If the production run fails, exit with an error message.
        echo "Production MD run failed. Check $run_dir/md_0_1_${replicate}_error.log for details."
        exit 1
  fi

  # Fit our trajectory to be centered on our peptide
  echo "Taking md_0_1_${replicate}.xtc and centering to remove PBC... produces md_0_1_${replicate}_fit.xtc."
  printf "1\n0\n" | gmx trjconv -s md_0_1_${replicate}.tpr \
    -f md_0_1_${replicate}.xtc \
    -o md_0_1_${replicate}_fit.xtc \
    -pbc mol -center
}

# Excute the run production function, where we are just performing another replicate from the same equilibrated starting point
run_production
echo "Replicate run and PDB centering complete!"

# Environment Variables Guide

WJM fully supports environment variables in job scripts.

## How It Works

Each job runs in its own bash shell. Environment variables, source commands, and module loads are preserved.

## Examples

### Basic Variables

```bash
#!/bin/bash
export MY_VAR="value"
export DATA_DIR="/path/to/data"
echo "MY_VAR: $MY_VAR"
```

### Source Files

```bash
#!/bin/bash
source /opt/software/setup.sh
source $HOME/.myapp_env
my_application --input data.txt
```

### Module Systems

```bash
#!/bin/bash
source /etc/profile.d/modules.sh
module load gcc/11.2.0
module load openmpi/4.1.2
mpirun -np 4 ./my_app
```

## Engineering Software

### OpenFOAM

```bash
#!/bin/bash
# WEIGHT: 100
source /opt/openfoam10/etc/bashrc
export OMP_NUM_THREADS=8
cd $CASE_DIR
blockMesh && simpleFoam
```

### ANSYS

```bash
#!/bin/bash
# WEIGHT: 150
export ANSYS_INC="/ansys_inc/v232"
export ANSYSLMD_LICENSE_FILE="1055@license-server"
ansys232 -b -i input.inp -o output.out -np 8
```

### MATLAB

```bash
#!/bin/bash
# WEIGHT: 100
export MATLAB_ROOT="/usr/local/MATLAB/R2023b"
matlab -batch "run('analysis.m')"
```

### COMSOL

```bash
#!/bin/bash
# WEIGHT: 200
export COMSOL_HOME="/usr/local/comsol61/multiphysics"
export LMCOMSOL_LICENSE_FILE="1718@license-server"
comsol batch -np 16 -inputfile model.mph
```

## GPU Jobs

WJM auto-sets `CUDA_VISIBLE_DEVICES`:

```bash
#!/bin/bash
# GPU: 0,1
echo "Using GPUs: $CUDA_VISIBLE_DEVICES"
python train.py --gpus 2
```

## Parallel Processing

### OpenMP
```bash
export OMP_NUM_THREADS=16
./my_openmp_app
```

### MPI
```bash
module load openmpi/4.1
mpirun -np 32 ./my_mpi_app
```

## Conda/Virtualenv

```bash
#!/bin/bash
source ~/miniconda3/etc/profile.d/conda.sh
conda activate my_env
python analysis.py
```

## Common Variables

| Variable | Purpose |
|----------|---------|
| OMP_NUM_THREADS | OpenMP threads |
| CUDA_VISIBLE_DEVICES | GPU selection (auto-set) |
| LD_LIBRARY_PATH | Library search path |

## Best Practices

- Use absolute paths
- Check software availability before running
- Set variables at script top
- Log environment info for debugging

## Troubleshooting

**Software not found:** Add to PATH
```bash
export PATH="/opt/software/bin:$PATH"
```

**Library not found:** Add to LD_LIBRARY_PATH
```bash
export LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"
```

**Module not found:** Source module init
```bash
source /etc/profile.d/modules.sh
```

See `examples/engineering/` for more examples.

# Engineering Software Examples

Job scripts for common engineering software with WJM.

## Examples

| Software | File | Description |
|----------|------|-------------|
| OpenFOAM | `openfoam_case.run` | CFD simulation |
| ANSYS | `ansys_batch.run` | FEA analysis |
| COMSOL | `comsol_batch.run` | Multiphysics |
| MATLAB | `matlab_batch.run` | Batch mode |
| Gerris | `gerris_simulation.run` | Flow solver |
| Modules | `module_environment.run` | Lmod/Environment Modules |

## Usage

```bash
# Customize the script
cp openfoam_case.run my_job.run
nano my_job.run   # Edit paths, license, etc.

# Submit
cd ../../src
wjm -qrun ../examples/engineering/my_job.run --weight 150
```

## OpenFOAM

```bash
#!/bin/bash
# WEIGHT: 100
source /opt/openfoam10/etc/bashrc
cd $CASE_DIR
blockMesh && simpleFoam
```

## ANSYS

```bash
#!/bin/bash
# WEIGHT: 150
export ANSYS_INC="/ansys_inc/v232"
export ANSYSLMD_LICENSE_FILE="1055@license-server"
ansys232 -b -i input.inp -o output.out -np 8
```

## MATLAB

```bash
#!/bin/bash
# WEIGHT: 100
export MATLAB_ROOT="/usr/local/MATLAB/R2023b"
matlab -batch "run('analysis.m')"
```

## Tips

- Use absolute paths
- Check software availability before running
- Set license variables early
- Log environment info at job start

See `../../docs/ENVIRONMENT_VARIABLES.md` for detailed guide.

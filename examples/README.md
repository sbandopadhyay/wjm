# WJM Examples

Ready-to-run job examples for WJM.

## Categories

**simple/** - Basic examples
- `hello_world.run` - Hello world
- `weighted_job.run` - Custom weight
- `python_script.run` - Python execution

**gpu/** - GPU jobs
- `gpu_training.run` - Single GPU
- `multi_gpu.run` - Multi-GPU

**pipeline/** - Multi-step workflows
- `preprocess.run` - Data preprocessing
- `train_model.run` - Model training
- `evaluate.run` - Evaluation

**engineering/** - OpenFOAM, ANSYS, MATLAB, etc.

## Usage

```bash
cd ~/wjm/src
wjm -qrun ../examples/simple/hello_world.run
wjm -qrun ../examples/gpu/gpu_training.run --priority high
```

## Customize

```bash
cp simple/hello_world.run my_job.run
nano my_job.run
wjm -qrun my_job.run
```

See [TUTORIAL.md](../TUTORIAL.md) for more details.

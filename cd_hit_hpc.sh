#!/bin/bash
#load default hpc environment
module load hpc-env/8.3
#load cd-hit module
module load CD-HIT/4.8.1-iccifort-2019b
# Create a temporary directory for the job in local storage
TMPDIR=/scratch/$USER/$SLURM_JOBID
export TMPDIR
mkdir -p $TMPDIR

while : ; do
    case $1 in
      -i)
            shift
            inDir=$1
            shift
            ;;
        -m)
            shift
            m=$1
            shift
            ;;
        -n)
            shift
            n=$1
            shift
            ;;

        -h|--help)
            echo "Heul leiser"
            exit
            ;;
        *)  if [ -z "$1" ]; then break; fi
            inDir=$1
            shift
            ;;
    esac
done

main_dir=.
out_dir=${main_dir}/clusters/$n

mkdir -p ${out_dir}

for s in $(cat Files_${n}.txt); do
    echo "started cd-hit with jobs "$s"..."
    cd-hit -in ${main_dir}/split/${s} -o ${out_dir} -M $m -c 0.9 -T $t
done
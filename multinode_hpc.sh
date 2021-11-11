#!/bin/bash
inDir=/gss/work/fasa8837/clust
njobs=4
p=mpcs.p 
rt_d=20
rt_h=0
splDir=/user/fasa8837
while : ; do
    case $1 in
    	-i)
            shift
            inDir=$1
            shift
            ;;
        -njobs)
            shift
            njobs=$1
            shift
            ;;
        -p)
            shift
            p=$1
            shift
            ;;
        -mail)
            shift
            mail=$1
            shift
            ;;
        -rt_d)
            shift
            rt_d=$1
            shift
            ;;
        -rt_h)
            shift
            rt_h=$1
            shift
            ;;
        -splDir)
            shift
            spl=$1
            shift
            ;;

        -h|--help)
            echo "Splitting protein multifasta into several files and submitting multiple Jobs to HPC"
            echo ""
            echo "USAGE:"
            echo "-i [PATH]: Directory containing protein multifasta"
            echo "-njobs [INT]: Number of jobs to submit to HPC. Multifasta will be split into [njobs] chunks for parallel processing. Samples will be equally distibuted among jobs."
            echo "-p [OPTION]: HPC partition. default: mpcb.p (nodes: 128, max. threads: 16, max memory: 495GB), other options: mpcs.p (nodes: 158, max. threads: 24, max memory: 243GB), mpcp.p (nodes: 2, max. threads: 40, max memory: 1975G)"
            echo "-mail [EMAIL ADDRESS]: E-mail address for notification in case of FAIL or FINISH of jobs"
            echo "-rt_d [INT]: max. job runtime in Days. Jobs > 21d will not start! default: 10"
            echo "-rt_h [INT]: max. job runtime in hours - will be added to -rt_d. Jobs > 21d will not start! default: 0"
            echo "-splDir [PATH] path to split_fasta.pl"
            exit
            ;;
        *)  if [ -z "$1" ]; then break; fi
            inDir=$1
            shift
            ;;
    esac
done

if [[ "$inDir" == 0 ]]; then
    echo ""
    echo ""
    echo "USAGE:"
    echo "--i [PATH]: Directory containing protein multifasta"
    echo "-njobs [INT]: Number of jobs to submit to HPC. Multifasta will be split into [njobs] chunks for parallel processing. Samples will be equally distibuted among jobs."
    echo "-p [OPTION]: HPC partition. default: mpcb.p (nodes: 128, max. threads: 16, max memory: 495GB), other options: mpcs.p (nodes: 158, max. threads: 24, max memory: 243GB), mpcp.p (nodes: 2, max. threads: 40, max memory: 1975G)"
    echo "-mail [EMAIL ADDRESS]: E-mail address for notification in case of FAIL or FINISH of jobs"
    echo "-rt_d [INT]: max. job runtime in Days. Jobs > 21d will not start! default: 10"
    echo "-rt_h [INT]: max. job runtime in hours - will be added to -rt_d. Jobs > 21d will not start! default: 0"
    echo "-splDir [PATH] path to split_fasta.pl"
    exit
fi

# if [[ "${p}" != "mpcb.p" || "${p}" != "mpcb.s"  || "${p}" != "mpcp.p" ]]; then
#     echo "ERROR: No valid partition selected!"
#     echo "-p [OPTION]: HPC partition. default: mpcb.p (nodes: 128, max. threads: 16, max memory: 495GB), other options: mpcs.p (nodes: 158, max. threads: 24, max memory: 243GB), mpcp.p (nodes: 2, max. threads: 40, max memory: 1975G)"
#     exit
# fi

if [[ "$p" == "mpcb.p" ]]; then
    M=495
    T=16
fi
if [[ "$p" == "mpcs.p" ]]; then
    M=243
    T=24
fi
if [[ "$p" == "mpcp.p" ]]; then
    M=1975
    T=40
fi
echo "using "$p" partition"
echo "Splitting protein multifasta into "$njobs" files and submitting "$njobs" Jobs to HPC"

##################################################################################################
#Data prep and file splitting                                                                    #
##################################################################################################

#count number of sequences in protein multifasta
nseq=$(grep -c "^>" $inDir/*.fasta)
#divide sequences by number of jobs
jseq=$(expr $nseq / $njobs)
#split protein multifasta by $njobs
mkdir -p $inDir/split
#split multifasta with Splitfasta.pl
perl $splDir/Splitfasta.pl -i $inDir/*.fasta -o $inDir/split/split_prot -n $jseq
#rename files to .fasta files
cd $inDir/split
for f in $inDir/split/* ; do 
    mv -- "$f" "${f}.fasta"
done
cd $inDir

echo "Multifasta input is split into "njobs" files with approximately "$jseq" each"

##################################################################################################
#multijob submission                                                                             #
##################################################################################################
( cd $inDir/split && ls *.fasta ) > Files.txt

nFiles=$(cat ./Files.txt | wc -l)
nSamples=$(echo "scale=1;($nFiles/$njobs)" | bc | awk '{print ($0-int($0)<0.0001)?int($0):int($0)+1}')

c=0
for ((i=1; i<=njobs; i++)); do
    if [[ "$i" == 1 ]]; then
        from=$(echo $i)
    else
        from=$(echo $c)
    fi

    if [[ "$i" < "$njobs" ]]; then
        to=$(echo "$(($i * $nSamples))")
    else
        to=$(echo "$nFiles")
    fi
    
    c=$(echo "$(($to + 1))")
    echo "FROM: $from"
    echo "TO: $to"
    awk "NR==$from, NR==$to" Files.txt
    awk "NR==$from, NR==$to" Files.txt > Files_${i}.txt

    echo "#!/bin/bash" > JOB_$i.slurm
    echo "#SBATCH --ntasks=1" >> JOB_$i.slurm
    echo "#SBATCH --cpus-per-task=$t" >> JOB_$i.slurm
    echo "#SBATCH --mem=${m}G" >> JOB_$i.slurm
    echo "#SBATCH --time=${rt_d}-${rt_h}:00:00" >> JOB_$i.slurm
    echo "#SBATCH --output=LOG.%A.out" >> JOB_$i.slurm
    echo "#SBATCH --error=ERRORS.%A.err" >> JOB_$i.slurm
    echo "#SBATCH --mail-type=START,END,FAIL" >> JOB_$i.slurm
    echo "#SBATCH --mail-user=$mail" >> JOB_$i.slurm
    echo "#SBATCH --partition=$p" >> JOB_$i.slurm
    echo ""
    echo "##### SBATCH --array=1-10%3" >> JOB_$i.slurm
    echo ""
    echo "bash cd_hit_hpc.sh -i $inDir -M $m -T $t -n $i" >> JOB_$i.slurm

    sbatch JOB_$i.slurm
done
#!/bin/bash

# use traditional way for conda environment
source /opt/anaconda3/etc/profile.d/conda.sh
conda activate alphafold_2.3

# User configuration
db_dir=/mnt/db
pretrained_data_dir=/mnt/db/weights/alphafold/

# automatically determined directory
af_official_repo=$(readlink -f $(dirname $0))
dir=$PWD

out_dir=$dir/output
res_dir=$dir/res

usage() {
  echo ""
  echo "Usage: $0 <OPTIONS>"
  echo "Required Parameters:"
  # edited by Yinying
  echo "-f <fasta>  input fasta file"
  echo "-m <model_preset>  Choose preset model configuration - the monomer model, the monomer model with extra ensembling, monomer model with pTM head, or multimer model"
  echo "-n <num_multimer_predictions_per_model>       How many predictions (each with a different random seed) will be generated per model"
  echo "-j <nproc>  How many processors will be used in the feature construction. Default: 8"
  echo "-t <template_date>  Maximum template release date to consider (ISO-8601 format - i.e. YYYY-MM-DD). Important if folding historical test sets. Default: 2023-03-15"
  echo "-e <num_ensemble>  Ensemble Number for pre-inference"
  echo "-p <pretrained_data_date> Pretrained data release date to consider (ISO-8601 format - i.e. YYYY-MM-DD). Important if folding historical test sets. Default: 2022-12-06 "
  echo "-r <run_relax>  Run relax to {best, all, none} model(s). Default: best"
  echo "-c <clean_run>  Make a clean run, full results (massive pkls) will be deleted. Default: false"
  echo ""
  exit 1
}

while getopts ":f:m:t:n:e:j:p:r:c:" i; do
  case "${i}" in

  f)
    fasta=$OPTARG
    ;;
  m)
    model_preset=$OPTARG
    ;;

  t)
    max_template_date=$OPTARG
    ;;
  n)
    num_multimer_predictions_per_model=$OPTARG
    ;;
  j)
    nproc=$OPTARG
    ;;
  e)
    num_ensemble=$OPTARG
    ;;
  p)
    pretrained_data_date=$OPTARG
    ;;
  r)
    run_relax=$OPTARG
    ;;
  c)
    clean_run=$OPTARG
    ;;
  *)
    echo Unknown argument!
    usage
    ;;

  esac
done

if [[ "$max_template_date" == "" ]]; then
  max_template_date=2023-03-15
fi

if [[ "$max_template_date" == "no" ]]; then
  max_template_date=1900-01-01
fi

if [[ "$pretrained_data_date" == "" ]]; then
  pretrained_data_date=2022-12-06
elif [[ ! -d ${pretrained_data_dir}/${pretrained_data_date}/ ]]; then
  echo "ERROR: Unknown pretrained_data_date ${pretrained_data_date} or the pretrained_data_dir ${pretrained_data_dir} inaccessible. "
  usage

fi

if [[ "$nproc" == "" ]]; then
  nproc=8
fi


# edited by Yinying
if [[ "$model_preset" == "" ]]; then
  model_preset="auto"
fi

if [[ "$run_relax" == "all" || "$run_relax" == "best" || "$run_relax" == "none" ]]; then
  run_relax=$run_relax
else
  run_relax=best
fi

if [[ "$clean_run" == "" || "$clean_run" == "false" ]]; then
  clean_run=false
else
  clean_run=true
fi




if [[ "$model_preset" != "auto" && "$model_preset" != "monomer" && "$model_preset" != "monomer_casp14" && "$model_preset" != "monomer_ptm" && ! "$model_preset" =~ "multimer" ]]; then
  echo "Unknown model_preset! "
  usage
fi

echo "process will start at : "
date
echo "++++++++++++++++++++++++++++++++++++++++"

mkdir $res_dir
mkdir $out_dir
mkdir $res_dir/models
mkdir $res_dir/lite
mkdir $res_dir/full
mkdir $dir/processed

AF_process() {

  local dir=$1
  local i=$2
  local decoy_name=${i%.fasta}

  num_sequence_per_fasta=$(grep '^>' $dir/$i |wc -l)

  if [[ "$model_preset" == "auto" ]]; then
    if [[ $num_sequence_per_fasta -eq 1 ]]; then 
      model_preset="monomer"
    else
       model_preset="multimer"
    fi
  fi

  echo "Setting model_preset to $model_preset due to sequence number $num_sequence_per_fasta in file $dir/$i"

  # set default num_ensemble
  if [[ "$model_preset" == "monomer" || "$model_preset" == "monomer_ptm" || "$model_preset" =~ "multimer" ]]; then
    if [[ "$num_ensemble" == "" ]]; then
      num_ensemble=1
    fi
  elif [[ "$model_preset" == "monomer_casp14" ]]; then
    if [[ "$num_ensemble" == "" ]]; then
      num_ensemble=8
    fi
  fi

  if [[ "$model_preset" =~ "multimer" ]]; then
    if [[ "$num_multimer_predictions_per_model" == "" ]]; then
      num_multimer_predictions_per_model=2
    fi
  else
    num_multimer_predictions_per_model=1
  fi


  if [[ "$decoy_name" == "" ]]; then
    echo "decoy_name ${decoy_name} is not valid!"
    exit 1
  fi

  cd $af_official_repo # fix error caused by some path configs.
  if [ ! -f $res_dir/lite/$decoy_name\_AF2_lite.tar.bz2 ]; then
    # not started yet??
    if [ ! -f $out_dir/$decoy_name/features.pkl ]; then
      echo File does not exist: $out_dir/$decoy_name/features.pkl
      echo Modeling is not started: $i
      cmd="bash $af_official_repo/run_feature_cpu.sh \
                  -d $db_dir \
                  -P ${pretrained_data_dir}/${pretrained_data_date}/ \
                  -o $out_dir \
                  -m $model_preset \
                  -n $num_multimer_predictions_per_model \
                  -j $nproc \
                  -f $dir/$i \
                  -t $max_template_date"
      echo "$cmd"
      eval "$cmd"
    else
      echo Find feature files in $out_dir/$decoy_name/features.pkl
      echo Skip the run_feature process: $decoy_name
    fi
    # featuring is not started yet, Skip this sequence.
    if [ ! -f $out_dir/$decoy_name/features.pkl ]; then
      echo File does not exist: $out_dir/$decoy_name/features.pkl
      echo Modeling is not started: $i
      echo Skip Modeling: $i
    else
      #
      echo Find feature files in $out_dir/$decoy_name/features.pkl
      if [[ ! -f $out_dir/$decoy_name/ranking_debug.json ]]; then
        echo Runing modeling process : $decoy_name
        local cmd="bash $af_official_repo/run_alphafold.sh \
                        -d $db_dir \
                        -P ${pretrained_data_dir}/${pretrained_data_date}/ \
                        -o $out_dir \
                        -m $model_preset \
                        -f $dir/$i \
                        -n $num_multimer_predictions_per_model \
                        -t $max_template_date \
                        -e $num_ensemble \
                        -r $run_relax"
      else
        echo Find Previous ranking: $out_dir/$decoy_name/ranking_debug.json
        echo Skip Modeling ...
      fi

      echo "$cmd"
      eval "$cmd"

      cd $out_dir &&
        echo Selecting best_model ...
      pushd $decoy_name
      for f in ranked*.pdb; do cp ${f} ${res_dir}/models/${decoy_name}_${f}; done
      popd

      # plot summary of af modeling results
      mkdir -p $res_dir/models/plot/$decoy_name
      python ${af_official_repo}/AlphaPickle.py --res_dir $decoy_name --save_dir $res_dir/models/plot/$decoy_name

      #cp $decoy_name/ranked_0.pdb $res_dir/best_model/${decoy_name}_ranked_0.pdb &&
      echo Collecting results files .... &&
        tar jcf $decoy_name\_AF2_lite.tar.bz2 --exclude *.pkl $decoy_name &&
        mv $decoy_name\_AF2_lite.tar.bz2 $res_dir/lite
      if [[ "$clean_run" == "false" ]]; then
        tar jcf $decoy_name\_AF2_full.tar.bz2 --remove-files $decoy_name &&
          mv $decoy_name\_AF2_full.tar.bz2 $res_dir/full &
      else
        rm -rf $decoy_name
      fi
    fi
  else
    echo Find modeling files in $res_dir/lite/$decoy_name\_AF2_lite.tar.bz2
    echo Skip the run_alphafold process: $decoy_name
  fi
}

if [[ "$fasta" == "" || ! -f $(readlink -f ${fasta}) ]]; then
  echo "No input fasta file, now we run alphafold to any FASTA files located in $PWD"
  cd $dir
  echo We are now in $(pwd)

  total=$(ls | grep .fasta | wc -l)
  fin=0
  rest=$total

  for i in $(ls | grep .fasta); do
    cd $dir
    # run processing ...
    AF_process $dir $i && let fin++ && let rest-- && mv $dir/$i $dir/processed
    # mv $dir/$i $dir/processed;
    #echo Sending final notify ....
    #python $af_official_repo/sms.py "$(whoami)" "$(awk -F'[/:]' -v user=$(whoami) '{if ($1 == user && $3 >= 1000 && $3 != 65534) print $5}' /etc/passwd)" "$(basename $dir)" $total $fin $rest
  done
  echo Sending final notify ....
  python $af_official_repo/sms.py "$(whoami)" "$(awk -F'[/:]' -v user=$(whoami) '{if ($1 == user && $3 >= 1000 && $3 != 65534) print $5}' /etc/passwd)" "$(basename $dir)" $total $fin $rest
else
  fasta=$(readlink -f ${fasta})
  echo "run alphafold to ${fasta}"
  dir=$(dirname $(readlink -f $fasta))
  fasta_fn=$(basename $fasta)
  cd $dir
  echo "We are now in $dir"
  AF_process $dir $fasta_fn
  wait
  echo Sending final notify ....
  python $af_official_repo/sms.py "$(whoami)" "$(awk -F'[/:]' -v user=$(whoami) '{if ($1 == user && $3 >= 1000 && $3 != 65534) print $5}' /etc/passwd)" "$(basename $fasta)" 1 1 0
fi

wait

echo "++++++++++++++++++++++++++++++++++++++++"

echo "process end at : "
date
cd $dir

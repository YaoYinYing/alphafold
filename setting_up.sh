# for A100 server jpas in ubuntu2004
# run the following as root

# user configuration
CONDA_PATH="/opt/anaconda3"
SOFTWARE_PATH='/software'
DB_PATH='/mnt/db/'

# basic tools
apt-get -y install aria2

mkdir -p $SOFTWARE_PATH

wget https://mirrors.bfsu.edu.cn/anaconda/archive/Anaconda3-2021.05-Linux-x86_64.sh

# install anaconda3, and set conda path to /opt/anaconda3/

bash Anaconda3-2021.05-Linux-x86_64.sh -bfp ${CONDA_PATH}

# setup conda repository
echo "channels:
  - defaults
  - https://USERNAME:PASSWORD@conda.graylab.jhu.edu
  - conda-forge
show_channel_urls: true
default_channels:
  - https://mirrors.bfsu.edu.cn/anaconda/pkgs/main
  - https://mirrors.bfsu.edu.cn/anaconda/pkgs/r
  - https://mirrors.bfsu.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.bfsu.edu.cn/anaconda/cloud
  msys2: https://mirrors.bfsu.edu.cn/anaconda/cloud
  bioconda: https://mirrors.bfsu.edu.cn/anaconda/cloud
  menpo: https://mirrors.bfsu.edu.cn/anaconda/cloud
  pytorch: https://mirrors.bfsu.edu.cn/anaconda/cloud
  simpleitk: https://mirrors.bfsu.edu.cn/anaconda/cloud
report_errors: false
" > ~/.condarc
# refresh the conda cache
conda clean -i



# alphafold official repo, with seperated featuring and modeling procedures.
cd $SOFTWARE_PATH
git clone https://github.com/YaoYinYing/alphafold.git
cd alphafold
git checkout main_next
alphafold_path=$SOFTWARE_PATH/alphafold/


# create the conda environment for alphafold
conda create  -n alphafold -y python=3.11 conda-forge::pysocks

conda activate alphafold
export  CUDA_VERSION=12.2.2
conda install --yes --channel nvidia cuda=${CUDA_VERSION}
conda install conda-forge::cuda-toolkit==${CUDA_VERSION}  conda-forge::cudnn=8.9 -y

conda install --yes --channel conda-forge openmm=8.0.0 pdbfixer
conda install -y -c bioconda hmmer==3.3.2 hhsuite==3.3.0 kalign2==2.04 -y

pip3 install --upgrade --no-cache-dir jax==0.4.26 jaxlib==0.4.26+cuda12.cudnn89 -f https://storage.googleapis.com/jax-releases/jax_cuda_releases.html

pip3 install -r requirements.txt --no-cache-dir 


# get chemical props
wget -q -P $alphafold_path/alphafold/common/ https://git.scicore.unibas.ch/schwede/openstructure/-/raw/7102c63615b64735c4941278d92b554ec94415f8/modules/mol/alg/src/stereo_chemical_props.txt


# database settings to avoid permission errors
# remember to rename each db file exactly the same as what it is in run_feature_cpu.sh and run_alphafold.sh


mkdir -p $DB_PATH/alphafold
pushd $DB_PATH/alphafold
# set the historical pretrained af parameters
awk '{
  split($0, arr, ",");
  if(arr[1]!="tag"){
    tag=arr[1];
    url=arr[2];
    short_name=arr[3];

    split(url,arr2,"/");
    filename=arr2[length(arr2)];
    print filename;

    # create directories
    system("mkdir "short_name);

    # downloading params
    system("pushd "short_name";if [[ -f "filename" && ! -f "filename".aria2c ]];then echo Find complete file "filename".; else aria2c -x 10 "url";fi; tar -xf "filename" ; rm -f "filename";parallel -k sha256sum {} ::: $(ls)  > "short_name".sha256; popd");

    }
  }'  $SOFTWARE_PATH/alphafold/pretrained_data_url.csv


chmod -R 755 $DB_PATH/




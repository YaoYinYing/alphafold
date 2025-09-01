
# determined directory
af_repo_scripts=$(readlink -f $(dirname $0))


awk '{split($0, arr, ",");
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
    system("
      if [[ -f "short_name"/"filename" && ! -f "short_name"/"filename".aria2c ]];then
        echo Find complete file "filename".;
      else
        aria2c -x 10 "url" --dir "short_name";
      fi;
      pushd "short_name";
        tar -xf "filename" ;
        rm -f "filename";parallel -k sha256sum {} ::: $(ls)  > "short_name".sha256;
      popd");
    }
  }' ${af_repo_scripts}/../pretrained_data_url.csv
#! /bin/bash

#David Shean
#dshean@gmail.com

#Utility to mosaic ntf files by DigitalGlobe CATID

#Function to grab tag from xml
#Note: can have multiple lines with same tag (e.g. SATID)
function gettag() {
    xml=$1
    tag=$2
    echo $(grep "$tag" $xml | awk -F'[<>]' '{print $3}' | head -1)
}

#Apply the wv_correct L1B CCD offset shifts
correct=true

#Number of parallel jobs to run - limited by memory
ncpu=4

#Output mosaic ndv
ndv=0

#Input directory
if [ ! -z "$1" ]; then
    dir=$1
else
    dir=$(pwd)
fi

cd $dir

t_start=$(date +%s)

ext=ntf
#ext=tif

ids=($(dg_get_ids.py .))

#Check for existing r100 and generate list of ntf to process
ntf_list=''
for id in ${ids[@]}; do
    outprefix=$id
    if [ -e ${outprefix}.r100.tif ]; then
        echo "Existing mosaic found: $(ls ${outprefix}.r100.tif)"
    else
        #This should catch all combinations of ntf, tif and various filename formats
        ntf_list+=" $(ls | grep -e "${id}" | grep -i P1BS | egrep 'ntf|tif' | grep -v 'corr')"
    fi
done

if [ ! -z "$ntf_list" ] ; then
    #Check to make sure correction is supported 
    xml1=$(echo $ntf_list | awk '{print $1}' | awk -F'.' '{print $1 ".xml"}')
    satid=$(gettag $xml1 'SATID')

    if [ "$satid" != "WV01" ] && [ "$satid" != "WV02" ] ; then
        echo "Input camera unsopported for wv_correct"
        correct=false
    fi

    if $correct ; then 
        #Check for missing corr files
        missing=()
        for ntf in $ntf_list ; do
            if [ ! -e ${ntf%.*}_corr.tif ] ; then
                missing+=($ntf)
            fi
        done
        if (( ${#missing[@]} != 0 )) ; then
            echo; date; echo
            echo "Running wv_correct for ${#missing[@]} subsections"
            echo
            #Note: wv_correct can't use more than 200% CPU, IO and memory bound
            echo parallel -v --delay 1 -j $ncpu 'wv_correct --threads 2 {} {.}.xml {.}_corr.tif; gdal_edit.py -a_nodata 0 {.}_corr.tif' ::: ${missing[@]}
            time parallel -v --delay 1 -j $ncpu 'wv_correct --threads 2 {} {.}.xml {.}_corr.tif; gdal_edit.py -a_nodata 0 {.}_corr.tif' ::: ${missing[@]}
        fi
        #Now create symlinks for xml
        for ntf in ${missing[@]} ; do 
            ln -sf ${ntf%.*}.xml ${ntf%.*}_corr.xml
        done
    fi
            
    #Generate r100.tif for each id
    #Note: GNU parallel can just take
    #dg_mosaic ::: 'cmd1' 'cmd2'
    arg_list=''
    mos_opt="--input-nodata-value 5 --output-nodata-value $ndv"

    #Fix seam offsets between subscenes
    #mos_opt+=" --fix-seams"

    for id in ${ids[@]}; do
        outprefix=$id
        if [ ! -e ${outprefix}.r100.tif ]; then
            if $correct ; then
                ntf_list=$(ls *${id}*_corr.tif)
            else
                ntf_list=$(ls *$id*.$ext)
            fi
            a="dg_mosaic $mos_opt --output-prefix $outprefix $ntf_list"
            arg_list+=\ \""$a"\"
        fi
    done

    echo; date; echo 
    echo "Running dg_mosaic for ${#ids[@]} ids"
    echo
    ncpu=2
    echo parallel -v --delay 1 -j $ncpu ::: $arg_list 
    eval time parallel -v --delay 1 -j $ncpu ::: $arg_list 
fi

t_end=$(date +%s)

t_diff=$(expr $t_end - $t_start)
t_diff_hr=$(printf '%0.2f' $(echo "$t_diff/3600" | bc -l))

echo; date; echo
echo "Total wall time (hr): $t_diff_hr"
echo

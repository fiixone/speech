#!/bin/sh
set -e

## 配置信息
filetype="*.wav"                             #文件格式 ("默认.wav/支持.mp3") 
filepath="/mnt/d/"                           #工程目录 (win10可修改至D盘 '/mnt/d/' 注意路径后斜杠不能少)
cut_time="59"                                #切片时间,建议不要60s.
filename=""                                  #文件名 注意文件名请勿带空格

APPKEY="kVcnfD9iW2XVZSMaLMrtLYIz"            #百度appkey
APPSECRET="O9o1O213UgG5LFn0bDGNtoRN3VWl2du6" #百度appsecret


## 视觉输出
CSI="\033["
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"

out_alert() {
    echo "${CYELLOW}[注意] $1${CEND}"
}

out_error() {
    echo "${CRED}[警告] $1${CEND}"
}

out_info() {
    echo "${CGREEN}[信息] $1${CEND}"
}

time_sleep() {
    sleep 1
}


## banner
banner_start() {
    echo "##########################################################"
    echo ' _____ _ _       ___               _____           _     '
    echo '|  ___(_|_)_  __/ _ \ _ __   ___  |_   _|__   ___ | |___ '
    echo '| |_  | | \ \/ / | | | `_ \ / _ \   | |/ _ \ / _ \| / __|'
    echo '|  _| | | |>  <| |_| | | | |  __/   | | (_) | (_) | \__ \'
    echo '|_|   |_|_/_/\_\\____/|_| |_|\___|   |_|\___/ \___/|_|___/'
    echo '                                      bilibili   @FiixOne '
    echo "##########################################################"
}

banner_end() {
    echo "##########################################################"
}

check_ffmpeg() {
    which ffmpeg 2>&1 >/dev/null
    if [ ! $? = 0 ]; then
        out_error "请安装ffmpeg,例: sudo apt-get install ffmpeg"
        banner_end
        exit 0
    fi

}

## 检测临时tmp目录
check_tmp() {
    if [ ! -d $filepath/tmp ]; then
        out_alert "创建tmp目录..."
        mkdir -p $filepath/tmp
    else
        out_alert "清理tmp目录..."
        rm -rf $filepath/tmp/* 2>&1 >/dev/null
    fi
}

## 文件列表展示
choose_file() {
    list=$(ls $filepath$filetype 2>/dev/null)
    banner_end
    local $res
    for i in $list; do
        nu=$(($nu + 1))
        echo "$nu)-$i"
    done
    banner_end
    read -p "请输入文件序号:" res

    if [ -z "$res" ]; then
        out_error "无选择,程序退出!"
        banner_end
        exit 0

    elif [ "$res" -le "$nu" ]; then
        banner_end
        cd $filepath
        filename="$(ls $filetype | head -$res | tail -1)"
        out_alert "请确认本次处理文件:$res)-[$filename]"
    else
        out_error "选择错误,程序退出..."
        banner_end
        exit 0
    fi

    if [ -f $filepath/$filename.txt ]; then
        out_error "已经识别文件[$filename.txt]已存在,删除或移动后重新操作！"
        banner_end
        exit 0
    fi

    read -p "输入y继续运行，任意键退出：" res
    banner_end
    if [ -z $res ]; then
        exit 0
    elif [ ${res} != "y" ]; then
        exit 0
    fi

    out_info "验证成功"
    banner_end
}

## 切片源文件
cut_file() {
    out_info "准备切片文件至tmp文件夹..."
    cd $filepath
    time_sleep
    ffmpeg -i $filename -f segment -segment_time $cut_time -c copy ./tmp/%02d$filename 2>&1 >/dev/null
    echo $?
    out_info "共计生成切片文件个数:  $(ls -l ./tmp | grep "^-" | wc -l)"
    banner_end
    time_sleep

    ## 转码采样16000 16位
    cd $filepath/tmp/
    out_info "------转码开始------"
    time_sleep

    listtmp=$(ls $filetype)
    for itmp in $listtmp; do
        info=$(ffprobe -show_streams $itmp)
        bits_per_sample=$(echo "$info" | grep "bits_per_sample" | sed s/bits_per_sample=//g)
        codec_name=$(echo "$info" | grep "codec_name" | sed s/codec_name=//g)
        sample_rate=$(echo "$info" | grep "sample_rate" | sed s/sample_rate=//g)
        channels=$(echo "$info" | grep "channels" | sed s/channels=//g)
        out_info "------转码[$itmp]中------"
        out_info "编码名:$codec_name"
        out_info "位:$bits_per_sample"
        out_info "采样率:$sample_rate"
        out_info "声道数:$channels"

        ffmpeg -y -acodec $codec_name -ac $channels -i $itmp -acodec pcm_s16le -f s16le -ac 1 -ar 16000 $itmp.pcm 2>&1 >/dev/null
        #  -ar $sample_rate
    done
    out_info "所有切片文件已经转码完成..."
    banner_end
}

## 百度语音识别

speech() {
    local $res
    out_info "开始在线识别语音？"
    read -p "输入y开始识别，任意键退出：" res
    if [ -z $res ]; then
        exit 0
    elif [ ${res} != "y" ]; then
        exit 0
    fi
    out_info "验证成功"
    banner_end

    API_URL="http://vop.baidu.com/server_api"
    # DEV_PID="1537" # 短语音识别标准版
    DEV_PID="8001" 
    token_url="https://aip.baidubce.com/oauth/2.0/token?grant_type=client_credentials&client_id=$APPKEY&client_secret=$APPSECRET"
    token_resp=$(curl -s "$token_url")
    token=$(echo "${token_resp}" | grep -oP '"access_token"\s*:\s*"\K.+?(?=")')
    ## MacOS grep not support Perl(-P) syntax, so we use perl instead ;)
    ## token=$(echo "${token_resp}" | perl -nle 'print $& if m{"access_token"\s*:\s*"\K.+?(?=")}' )
    out_info "Got token: $token\n"
    time_sleep
    ASR_URL="${API_URL}?dev_pid=${DEV_PID}&token=$token&cuid=123"

    ## 需要识别的文件
    # support pcm/wav/amr 格式，极速版额外支持m4a 格式
    FORMAT="pcm"
    RATE="16000"
    ## 极速版需要打开下面注释
    ## ASR_URL="${API_URL}?dev_pid=${DEV_PID}&lm_id={LM_ID}$&token=$token&cuid=123"
    headers="Content-Type: audio/$FORMAT;rate=$RATE"

    listpcm=$(ls *.pcm)
    banner_end
    out_info "准备识别文件如下:\n"
    echo "$listpcm\n"
    banner_end

    for ipcm in $listpcm; do
        echo "Request ASR...写入缓存txt中..."
        curl -X POST -s --data-binary "@$ipcm" -H "$headers" "$ASR_URL" > ./$ipcm.txt
        echo "$ipcm写入$filename.txt中..."
        sed -n 's/\[\"/\n/p' ./$ipcm.txt | sed -n 's/\"\]/\n/p' | sed -n '1p' >> $filepath/$filename.txt
        time_sleep
    done

    out_info "音频识别完成..."
    banner_end
}

## 识别文本转换行
speech_line() {
    local $res
    out_info "识别文本转换行"
    out_info "(本操作适合做字幕使用)"
    read -p "输入y开始修改格式，任意键退出：" res
    if [ -z $res ]; then
        exit 0
    elif [ ${res} != "y" ]; then
        exit 0
    fi

    out_info "验证成功"
    banner_end

    cd $filepath
    cp $filename.txt 换行版.$filename.txt

    sed -i ':label;N;s/\n//;b label' 换行版.$filename.txt
    sed -i 'y/。，？；：‘“、（）｀～！＠＃％＊/.,?;:\"\",()`~!@#%*/' 换行版.$filename.txt
    sed -i 's/,\|\./\n/g' 换行版.$filename.txt

    out_info "输出文件为: 换行版.$filename.txt"
    out_info "完成..."
    banner_end
}

## 开始
banner_start
check_ffmpeg
check_tmp
choose_file
cut_file
speech
speech_line

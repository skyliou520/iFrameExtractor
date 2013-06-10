//
//  H264_Save.c
//  iFrameExtractor
//
//  Created by Liao KuoHsun on 13/5/24.
//
//

// Reference ffmpeg\doc\examples\muxing.c
#include <stdio.h>
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "H264_Save.h"
//#include "libavformat/avio.h"

int vVideoStreamIdx = -1, vAudioStreamIdx = -1,  waitkey = 1;

// < 0 = error
// 0 = I-Frame
// 1 = P-Frame
// 2 = B-Frame
// 3 = S-Frame
static int getVopType( const void *p, int len )
{
    
    if ( !p || 6 >= len )
    {
        fprintf(stderr, "getVopType() error");
        return -1;
    }
    
    unsigned char *b = (unsigned char*)p;
    
    // Verify VOP id
    if ( 0xb6 == *b )
    {
        b++;
        return ( *b & 0xc0 ) >> 6;
    } // end if
    
    switch( *b )
    {
        case 0x65 : return 0;
        case 0x61 : return 1;
        case 0x01 : return 2;
    } // end switch
    
    return -1;
}

void h264_file_close(AVFormatContext *fc)
{
    if ( !fc )
        return;
    
    av_write_trailer( fc );
    
    if ( fc->oformat && !( fc->oformat->flags & AVFMT_NOFILE ) && fc->pb )
        avio_close( fc->pb );
    
    av_free( fc );
}



// Since the data may not from ffmpeg as AVPacket format
void h264_file_write_frame(AVFormatContext *fc, int vStreamIdx, const void* p, int len, int64_t dts, int64_t pts )
{
    AVStream *pst = NULL;
    if ( 0 > vVideoStreamIdx )
        return;
    
    // may be audio or video
    pst = fc->streams[ vStreamIdx ];
    
    // Init packet
    AVPacket pkt;
    av_init_packet( &pkt );
    if(vStreamIdx==vVideoStreamIdx)
    {
        pkt.flags |= ( 0 >= getVopType( p, len ) ) ? AV_PKT_FLAG_KEY : 0;
        //pkt.flags |= AV_PKT_FLAG_KEY;
    }
    pkt.stream_index = pst->index;
    pkt.data = (uint8_t*)p;
    pkt.size = len;
    
#if PTS_DTS_IS_CORRECT == 1
    pkt.dts = dts;
    pkt.pts = pts;
#else
    pkt.dts = AV_NOPTS_VALUE;
    pkt.pts = AV_NOPTS_VALUE;
#endif
    // TODO: mark or unmark the log
    //fprintf(stderr, "dts=%lld, pts=%lld\n",dts,pts);
    // av_write_frame( fc, &pkt );
    av_interleaved_write_frame( fc, &pkt );
}

void h264_file_write_frame2(AVFormatContext *fc, int vStreamIdx, AVPacket *pPkt )
{    
    av_interleaved_write_frame( fc, pPkt );
}


int h264_file_create(const char *pFilePath, AVFormatContext *fc, AVCodecContext *pCodecCtx,AVCodecContext *pAudioCodecCtx, double fps, void *p, int len )
{
    int vRet=0;
    AVOutputFormat *of=NULL;
    AVStream *pst=NULL, *pst2=NULL;
    AVCodecContext *pcc=NULL, *pcc2=NULL;
    
    avcodec_register_all();
    av_register_all();
    av_log_set_level(AV_LOG_VERBOSE);

    if(!pFilePath)
    {
        fprintf(stderr, "FilePath no exist");
        return -1;
    }
    
    if(!fc)
    {
        fprintf(stderr, "AVFormatContext no exist");
        return -1;
    }
    fprintf(stderr, "file=%s\n",pFilePath);
    
    // Create container
    of = av_guess_format( 0, pFilePath, 0 );
    fc->oformat = of;
    strcpy( fc->filename, pFilePath );
    
    // Add video stream
    pst = avformat_new_stream( fc, 0 );
    vVideoStreamIdx = pst->index;
    NSLog(@"Video Stream:%d",vVideoStreamIdx);
    
    pcc = pst->codec;
    avcodec_get_context_defaults3( pcc, AVMEDIA_TYPE_VIDEO );

    // TODO: test here
    //*pcc = *pCodecCtx;
    
    // TODO: check ffmpeg source for "q=%d-%d", some parameter should be set before write header
    
    // Save the stream as origin setting without convert
    pcc->codec_type = pCodecCtx->codec_type;
    pcc->codec_id = pCodecCtx->codec_id;
    pcc->bit_rate = pCodecCtx->bit_rate;
    pcc->width = pCodecCtx->width;
    pcc->height = pCodecCtx->height;
    
#if PTS_DTS_IS_CORRECT == 1
    pcc->time_base.num = pCodecCtx->time_base.num;
    pcc->time_base.den = pCodecCtx->time_base.den;
    pcc->ticks_per_frame = pCodecCtx->ticks_per_frame;
//    pcc->frame_bits= pCodecCtx->frame_bits;
//    pcc->frame_size= pCodecCtx->frame_size;
//    pcc->frame_number= pCodecCtx->frame_number;
    
//    pcc->pts_correction_last_dts = pCodecCtx->pts_correction_last_dts;
//    pcc->pts_correction_last_pts = pCodecCtx->pts_correction_last_pts;
    
    NSLog(@"time_base, num=%d, den=%d, fps should be %g",\
          pcc->time_base.num, pcc->time_base.den, \
          (1.0/ av_q2d(pCodecCtx->time_base)/pcc->ticks_per_frame));
#else
    if(fps==0)
    {
        double fps=0.0;
        AVRational pTimeBase;
        pTimeBase.num = pCodecCtx->time_base.num;
        pTimeBase.den = pCodecCtx->time_base.den;
        fps = 1.0/ av_q2d(pCodecCtx->time_base)/ FFMAX(pCodecCtx->ticks_per_frame, 1);
        NSLog(@"fps_method(tbc): 1/av_q2d()=%g",fps);
        pcc->time_base.num = 1;
        pcc->time_base.den = fps;
    }
    else
    {
        pcc->time_base.num = 1;
        pcc->time_base.den = fps;
    }
#endif
    // reference ffmpeg\libavformat\utils.c

    // For SPS and PPS in avcC container
    pcc->extradata = malloc(sizeof(uint8_t)*pCodecCtx->extradata_size);
    memcpy(pcc->extradata, pCodecCtx->extradata, pCodecCtx->extradata_size);
    pcc->extradata_size = pCodecCtx->extradata_size;
    
    // TODO: support audio recording
#if SUPPORT_AUDIO_RECORDING == 1
    // For Audio stream
    if(pAudioCodecCtx)
    {
        // Add video stream
#if 1
        pcc2 = avcodec_alloc_context3(pAudioCodecCtx->codec);
        pst2 = avformat_new_stream( fc, pcc2->codec );
        vVideoStreamIdx = pst2->index;
        NSLog(@"Audio Stream:%d",vVideoStreamIdx);
        
#else
        pst2 = avformat_new_stream( fc, pAudioCodecCtx->codec );
        vVideoStreamIdx = pst2->index;
        NSLog(@"Audio Stream:%d",vVideoStreamIdx);
        
        pcc2 = pst2->codec;
        avcodec_get_context_defaults3( pcc2, AVMEDIA_TYPE_AUDIO );
#endif
        pcc2->channels = pAudioCodecCtx->channels;
        pcc2->channel_layout = pAudioCodecCtx->channel_layout;
        pcc2->sample_rate = pAudioCodecCtx->sample_rate;
        pcc2->sample_fmt = pAudioCodecCtx->sample_fmt;
        pcc2->sample_aspect_ratio = pAudioCodecCtx->sample_aspect_ratio;
        
        if(pAudioCodecCtx->extradata_size!=0)
        {
            pcc2->extradata = malloc(sizeof(uint8_t)*pAudioCodecCtx->extradata_size);
            memcpy(pcc2->extradata, pAudioCodecCtx->extradata, pAudioCodecCtx->extradata_size);
            pcc2->extradata_size = pAudioCodecCtx->extradata_size;
        }
    }
#endif
    
    if(fc->oformat->flags & AVFMT_GLOBALHEADER)
    {
        pcc->flags |= CODEC_FLAG_GLOBAL_HEADER;
    }
    
    if ( !( fc->oformat->flags & AVFMT_NOFILE ) )
    {
        avio_open( &fc->pb, fc->filename, AVIO_FLAG_WRITE );
    }
    
    // dump format in console
    av_dump_format(fc, 0, pFilePath, 1);
    
    vRet = avformat_write_header( fc, NULL );
    if(vRet==0)
        return true;
    else
        return false;
}

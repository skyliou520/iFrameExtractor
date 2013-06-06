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
//#include "libavformat/avio.h"

int vStreamIdx = -1, waitkey = 1;

#if 1
// Read nal type from RTP payload
static int get_nal_type( const void *p, int len )
{
    unsigned char *b = (unsigned char*)p;
    
    if ( !b || 5 >= len )
    {
        fprintf(stderr, "get_nal_type() error");
        return -1;
    }
    
    if( b[0] || b[1] || 0x01!=b[2])
    {
        b++;
       if( b[0] || b[1] || 0x01!=b[2])
           return -1;
    }
    b += 3;
    return *b;
}
#else
// Read nal type from AVFrame of FFMPEG
static int get_nal_type( void *p, int len )
{
    // TODO
}
#endif

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
void h264_file_write_frame(AVFormatContext *fc, const void* p, int len, int dts, int pts )
{
    AVStream *pst = NULL;
    int vNalType = 0;
    if ( 0 > vStreamIdx )
        return;
    
    pst = fc->streams[ vStreamIdx ];
    
    // TODO: copy sps and pss to generate AVCC container box
    vNalType = get_nal_type(p, len ) ;
    if ( (vNalType==0x67) || (vNalType==0x68))
    {
        fprintf(stderr, "\ngot SPS\n");
    }
    // Init packet
    AVPacket pkt;
    av_init_packet( &pkt );
    pkt.flags |= ( 0 >= getVopType( p, len ) ) ? AV_PKT_FLAG_KEY : 0;
    pkt.stream_index = pst->index;
    pkt.data = (uint8_t*)p;
    pkt.size = len;
    
    // Wait for key frame
    if ( waitkey )
    {
        // #define AV_PKT_FLAG_KEY     0x0001 ///< The packet contains a keyframe
        if ( 0 == ( pkt.flags & AV_PKT_FLAG_KEY ) )
        {
            fprintf(stderr, "( pkt.flags & AV_PKT_FLAG_KEY ) == 0");
            return;
        }
        else
        {
            fprintf(stderr, "set waitkey = 0");
            waitkey = 0;
        }
    }
    
    // TODO: check here
#if 1
    pkt.dts = AV_NOPTS_VALUE;
    pkt.pts = AV_NOPTS_VALUE;
#else
    pkt.dts = dts;
    pkt.pts = pts;
#endif
    //fprintf(stderr, "dts=%d, pts=%d\n",dts,pts);
    // Should we add 0x000001 ourself ??
    av_interleaved_write_frame( fc, &pkt );
}


int h264_file_create( AVFormatContext *fc, AVCodecContext *pCodecCtx, double fps, void *p, int len )
{
    int vRet=0;
    AVOutputFormat *of=NULL;
    AVStream *pst=NULL;
    AVCodecContext *pcc=NULL;
    
    av_register_all();
    av_log_set_level(AV_LOG_DEBUG);
    
    // The first packet from network should be SPS
#if 0
    if ( 0x67 != get_nal_type( p, len ) )
    {
        fprintf(stderr, "get_nal_type( p, len ) = %d\n", get_nal_type( p, len ));
        return -1;
    }
#endif
    
    NSString *videoPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/test.mp4"];
    const char *file = [videoPath UTF8String];
    
    if(!fc)
    {
        fprintf(stderr, "AVFormatContext no exist");
        return -1;
    }
    fprintf(stderr, "file=%s\n",file);
    
    // Create container
    of = av_guess_format( 0, file, 0 );
    fc->oformat = of;
    strcpy( fc->filename, file );
    
    // Add video stream
    pst = avformat_new_stream( fc, 0 );
    vStreamIdx = pst->index;
        
    pcc = pst->codec;
    avcodec_get_context_defaults3( pcc, AVMEDIA_TYPE_VIDEO );

    // Save the stream as origin setting without convert
    pcc->codec_type = pCodecCtx->codec_type;
    pcc->codec_id = pCodecCtx->codec_id;
    pcc->bit_rate = pCodecCtx->bit_rate;
    pcc->width = pCodecCtx->width;
    pcc->height = pCodecCtx->height;
    
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
    
    // reference ffmpeg\libavformat\utils.c
    
    
//    pcc->gop_size = pCodecCtx-> gop_size;
//    pcc->pix_fmt = pCodecCtx-> pix_fmt;
    
    
    //pcc->compression_level = pCodecCtx->compression_level;
    //->delay = pCodecCtx->delay;
    // For MP4 ftyp container
    //pcc->profile = pCodecCtx->profile;
    
    // For Audio stream
    //    pcc->channels = pCodecCtx->channels;
    //    pcc->sample_rate = pCodecCtx->sample_rate;
    //    pcc->sample_fmt = pCodecCtx->sample_rate;
    //    pcc->sample_aspect_ratio = pCodecCtx->sample_aspect_ratio;
    
    // For SPS and PPS in avcC container
    pcc->extradata = malloc(sizeof(uint8_t)*pCodecCtx->extradata_size);
    memcpy(pcc->extradata, pCodecCtx->extradata, pCodecCtx->extradata_size);
    pcc->extradata_size = pCodecCtx->extradata_size;

    
    if(fc->oformat->flags & AVFMT_GLOBALHEADER)
    {
        pcc->flags |= CODEC_FLAG_GLOBAL_HEADER;
    }
    
    if ( !( fc->oformat->flags & AVFMT_NOFILE ) )
    {
        avio_open( &fc->pb, fc->filename, AVIO_FLAG_WRITE );
    }
    
    // dump format in console
    av_dump_format(fc, 0, file, 1);
    
    vRet = avformat_write_header( fc, NULL );
    if(vRet==0)
        return true;
    else
        return false;
}

#if 0
main()
{
    // Initialize a new format context for writing file
    AVFormatContext *fc = NULL;
    
    if(veVideoRecordState!=eH264RecIdle)
    {
        switch(veVideoRecordState)
        {
            case eH264RecInit:
            {
                if ( !fc )
                {
                    fc = avformat_alloc_context();
                    h264_file_create( fc, buf, sz );
                }
            }
                break;
                
            case eH264RecActive:
            {
                if ( fc )
                {
                    h264_file_write_frame( fc, buf, sz );
                }
                else
                {
                    NSLog(@"fc no exist");
                }
            }
                break;
                
            case eH264RecClose:
            {
                if ( fc )
                {
                    h264_file_close(fc);
                    fs = NULL;
                }
                else
                {
                    NSLog(@"fc no exist");
                }
                veVideoRecordState = eH264RecIdle;
            }   
                break;
                
            default:
                if ( fc )
                {
                    h264_file_close(fc);   
                    fs = NULL;
                }         
                NSLog(@"[ERROR] unexpected veVideoRecordState!!");
                veVideoRecordState = eH264RecIdle;
                break;
        }
    }
}
#endif
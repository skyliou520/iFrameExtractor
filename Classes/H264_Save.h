//
//  H264_Save.h
//  iFrameExtractor
//
//  Created by Liao KuoHsun on 13/5/24.
//
//

#ifndef iFrameExtractor_H264_Save_h
#define iFrameExtractor_H264_Save_h

extern int  h264_file_create( AVFormatContext *fc, AVCodecContext *pCodecCtx, void *p, int len );
extern void h264_file_write_frame(AVFormatContext *fc, const void* p, int len );
extern void h264_file_close(AVFormatContext *fc);

typedef enum
{
    eH264RecIdle = 0,
    eH264RecInit,
    eH264RecActive,
    eH264RecClose
} eH264RecordState;


#endif

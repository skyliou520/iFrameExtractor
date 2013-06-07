//
//  Video.m
//  iFrameExtractor
//
//  Created by lajos on 1/10/10.
//  Copyright 2010 www.codza.com. All rights reserved.
//

#import "VideoFrameExtractor.h"
#import "Utilities.h"
#import <AssetsLibrary/AssetsLibrary.h>
@interface VideoFrameExtractor (private)
-(void)convertFrameToRGB;
-(UIImage *)imageFromAVPicture:(AVPicture)pict width:(int)width height:(int)height;
-(void)savePicture:(AVPicture)pFrame width:(int)width height:(int)height index:(int)iFrame;
-(void)setupScaler;
@end

@implementation VideoFrameExtractor

@synthesize outputWidth, outputHeight;


// 20130524 albert.liao modified start

// 20130524 albert.liao modified start
@synthesize bSnapShot, veVideoRecordState, RecordingTimer;

- (void) SnapShot_AlertView:(NSError *)error
{
    UIAlertView *alert=nil;
    
    if (error)
    {
        // TODO: display different error message
        alert = [[UIAlertView alloc] initWithTitle:@"Warning"
                                           message:@"The Storage is full!\nFail to save captured image!"
                                          delegate:self cancelButtonTitle:@"Ok"
                                 otherButtonTitles:nil];
    }
    else // All is well
    {
        alert = [[UIAlertView alloc] initWithTitle:@"Success"
                                           message:@"Image Has been captured in Camera Roll successfully"
                                          delegate:self cancelButtonTitle:@"Ok"
                                 otherButtonTitles:nil];
    }
    [alert show];
    alert = nil;
}


- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    [self SnapShot_AlertView:error];
}
// 20130524 albert.liao modified end

-(void)setOutputWidth:(int)newValue {
	if (outputWidth == newValue) return;
	outputWidth = newValue;
	[self setupScaler];
}

-(void)setOutputHeight:(int)newValue {
	if (outputHeight == newValue) return;
	outputHeight = newValue;
	[self setupScaler];
}

-(UIImage *)currentImage {
	if (!pFrame->data[0]) return nil;
	[self convertFrameToRGB];
    
    // 20130524 albert.liao modified start
    // Save the image and clear the bSnapShot flag
    if(self.bSnapShot==YES)
    {
            UIImage *myimg=nil;
            AVPicture picture_tmp;
            struct SwsContext *img_convert_ctx_tmp;
            avpicture_alloc(&picture_tmp, PIX_FMT_RGB24, pFrame->width, pFrame->height);
            img_convert_ctx_tmp = sws_getContext(pCodecCtx->width,
                                                 pCodecCtx->height,
                                                 pCodecCtx->pix_fmt,
                                                 pFrame->width,
                                                 pFrame->height,
                                                 PIX_FMT_RGB24,
                                                 SWS_FAST_BILINEAR, NULL, NULL, NULL);
            
            sws_scale (img_convert_ctx_tmp, (const uint8_t **)pFrame->data, pFrame->linesize,
                       0, pCodecCtx->height,
                       picture_tmp.data, picture_tmp.linesize);
            
            myimg = [self imageFromAVPicture:picture_tmp width:pFrame->width height:pFrame->height];
            
            UIImageWriteToSavedPhotosAlbum(myimg, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
            self.bSnapShot = NO;
        
    }
    // 20130524 albert.liao modified end    
    
	return [self imageFromAVPicture:picture width:outputWidth height:outputHeight];
}

-(double)duration {
	return (double)pFormatCtx->duration / AV_TIME_BASE;
}

-(double)currentTime {
    AVRational timeBase = pFormatCtx->streams[videoStream]->time_base;
    return packet.pts * (double)timeBase.num / timeBase.den;
}

-(int)sourceWidth {
	return pCodecCtx->width;
}

-(int)sourceHeight {
	return pCodecCtx->height;
}

-(id)initWithVideo:(NSString *)moviePath {
	if (!(self=[super init])) return nil;
 
    AVCodec         *pCodec, *pCodecAudio;
		
    // Register all formats and codecs
    avcodec_register_all();
    av_register_all();
    
    // 20130524 albert.liao modified start
	avformat_network_init();
    // 20130524 albert.liao modified end
    
    // Open video file
    AVDictionary *opts = 0;
    //int ret = av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    
    if(avformat_open_input(&pFormatCtx, [moviePath cStringUsingEncoding:NSASCIIStringEncoding], NULL, &opts) != 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
        goto initError;
    }
	av_dict_free(&opts);
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
        goto initError;
    }
    
    // Find the first video stream
    if ((videoStream =  av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, &pCodec, 0)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a video stream in the input file\n");
        goto initError;
    }
	
    if ((audioStream =  av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &pCodecAudio, 0)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a video stream in the input file\n");
        goto initError;
    }
    
    // Get a pointer to the codec context for the video stream
    pCodecCtx = pFormatCtx->streams[videoStream]->codec;
    
    // Find the decoder for the video stream
    pCodec = avcodec_find_decoder(pCodecCtx->codec_id);
    if(pCodec == NULL) {
        av_log(NULL, AV_LOG_ERROR, "Unsupported codec!\n");
        goto initError;
    }
	
    // Open codec
    if(avcodec_open2(pCodecCtx, pCodec, NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open video decoder\n");
        goto initError;
    }
	
    // Allocate video frame
    pFrame = avcodec_alloc_frame();
			
	outputWidth = pCodecCtx->width;
	self.outputHeight = pCodecCtx->height;
			
	return self;
	
initError:
	[self release];
	return nil;
}


-(void)setupScaler {

	// Release old picture and scaler
	avpicture_free(&picture);
	sws_freeContext(img_convert_ctx);	
	
	// Allocate RGB picture
	avpicture_alloc(&picture, PIX_FMT_RGB24, outputWidth, outputHeight);
	
	// Setup scaler
	static int sws_flags =  SWS_FAST_BILINEAR;
	img_convert_ctx = sws_getContext(pCodecCtx->width, 
									 pCodecCtx->height,
									 pCodecCtx->pix_fmt,
									 outputWidth, 
									 outputHeight,
									 PIX_FMT_RGB24,
									 sws_flags, NULL, NULL, NULL);
	
}

-(void)seekTime:(double)seconds {
	AVRational timeBase = pFormatCtx->streams[videoStream]->time_base;
	int64_t targetFrame = (int64_t)((double)timeBase.den / timeBase.num * seconds);
	avformat_seek_file(pFormatCtx, videoStream, targetFrame, targetFrame, targetFrame, AVSEEK_FLAG_FRAME);
	avcodec_flush_buffers(pCodecCtx);
}

-(void)dealloc {
	// Free scaler
	sws_freeContext(img_convert_ctx);	

	// Free RGB picture
	avpicture_free(&picture);
    
    // Free the packet that was allocated by av_read_frame
    av_free_packet(&packet);
	
    // Free the YUV frame
    av_free(pFrame);
	
    // Close the codec
    if (pCodecCtx) avcodec_close(pCodecCtx);
	
    // Close the video file
    if (pFormatCtx) avformat_close_input(&pFormatCtx);
	
	[super dealloc];
}

-(void)StopRecording:(NSTimer *)timer {
    veVideoRecordState = eH264RecClose;
    NSLog(@"eH264RecClose");
    [timer invalidate];
}

-(BOOL)stepFrame {
	// AVPacket packet;
    int frameFinished=0;
    static bool bFirstIFrame=false;

    while(!frameFinished && av_read_frame(pFormatCtx, &packet)>=0) {
        // Is this a packet from the video stream?
        if(packet.stream_index==videoStream) {
            
            
            // 20130525 albert.liao modified start
//            fprintf(stderr, "packet len=%d, Byte=%02X%02X%02X%02X%02X%02X%02X%02X, State=%d\n",\
                    packet.size, packet.data[0],packet.data[1],packet.data[2],packet.data[3], packet.data[4],packet.data[5],packet.data[6],packet.data[7],veVideoRecordState);
            
            // Decode video frame
            avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet);
        


            // Initialize a new format context for writing file
            if(veVideoRecordState!=eH264RecIdle)
            {
                switch(veVideoRecordState)
                {
                    case eH264RecInit:
                    {
                        if ( !pFormatCtx_Record )
                        {
                            int bFlag = 0;
                            NSString *videoPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/test.mp4"];
//                            NSString *videoPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/test.mp4"];
                            const char *file = [videoPath UTF8String];
                            pFormatCtx_Record = avformat_alloc_context();
                            bFlag = h264_file_create(file, pFormatCtx_Record, pCodecCtx,/*fps*/0.0, packet.data, packet.size );
                            
                            if(bFlag==true)
                            {
                                veVideoRecordState = eH264RecActive;
                                fprintf(stderr, "h264_file_create success\n");                                
                            }
                            else
                            {
                                veVideoRecordState = eH264RecIdle;
                                fprintf(stderr, "h264_file_create error\n");
                            }
                        }
                    }
                    //break;
                        
                    case eH264RecActive:
                    {
                        if((packet.flags&AV_PKT_FLAG_KEY)==AV_PKT_FLAG_KEY)
                        {
                            bFirstIFrame=TRUE;
#if 0
                            NSRunLoop *pRunLoop = [NSRunLoop currentRunLoop];
                            [pRunLoop addTimer:RecordingTimer forMode:NSDefaultRunLoopMode];
#else
                            [NSTimer scheduledTimerWithTimeInterval:5.0//2.0
                                                             target:self
                                                           selector:@selector(StopRecording:)
                                                           userInfo:nil
                                                            repeats:NO];
#endif
                        }
                        
                        // Record audio when 1st i-Frame is obtained
                        if(bFirstIFrame==TRUE)
                        {

                            

                            
                            if ( pFormatCtx_Record )
                            {
                                h264_file_write_frame( pFormatCtx_Record, packet.data, packet.size, packet.dts, packet.pts);
                            }
                            else
                            {
                                NSLog(@"pFormatCtx_Record no exist");
                            }
                        }
                    }
                    break;
                        
                    case eH264RecClose:
                    {
                        if ( pFormatCtx_Record )
                        {
                            h264_file_close(pFormatCtx_Record);
                            
                            // 20130607 Test
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void)
                            {
                                ALAssetsLibrary *library = [[ALAssetsLibrary alloc]init];
                                NSString *filePathString = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/test.mp4"];
                                NSURL *filePathURL = [NSURL fileURLWithPath:filePathString isDirectory:NO];
                                if(1)// ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:filePathURL])
                                {
                                    [library writeVideoAtPathToSavedPhotosAlbum:filePathURL completionBlock:^(NSURL *assetURL, NSError *error){
                                        if (error) {
                                            // TODO: error handling
                                            NSLog(@"writeVideoAtPathToSavedPhotosAlbum error");
                                        } else {
                                            // TODO: success handling
                                            NSLog(@"writeVideoAtPathToSavedPhotosAlbum success");
                                        }
                                    }];
                                }
                                [library release];
                            });
                            
                            pFormatCtx_Record = NULL;
                            NSLog(@"h264_file_close() is finished");
                        }
                        else
                        {
                            NSLog(@"fc no exist");
                        }
                        bFirstIFrame = false;
                        veVideoRecordState = eH264RecIdle;
                        
                        
                        
                    }
                    break;
                        
                    default:
                        if ( pFormatCtx_Record )
                        {
                            h264_file_close(pFormatCtx_Record);
                            pFormatCtx_Record = NULL;
                        }
                        NSLog(@"[ERROR] unexpected veVideoRecordState!!");
                        veVideoRecordState = eH264RecIdle;
                        break;
                }
            }
        }
        else if(packet.stream_index==audioStream)
        {
            ;
        }
        else
        {
            fprintf(stderr, "packet len=%d, Byte=%02X%02X%02X%02X%02X\n",\
                    packet.size, packet.data[0],packet.data[1],packet.data[2],packet.data[3], packet.data[4]);
        }
        // 20130525 albert.liao modified end
	}
	return frameFinished!=0;
}

-(void)convertFrameToRGB {	
	sws_scale (img_convert_ctx, (const uint8_t **)pFrame->data, pFrame->linesize,
			   0, pCodecCtx->height,
			   picture.data, picture.linesize);	
}

-(UIImage *)imageFromAVPicture:(AVPicture)pict width:(int)width height:(int)height {
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
	CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, pict.data[0], pict.linesize[0]*height,kCFAllocatorNull);
	CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGImageRef cgImage = CGImageCreate(width, 
									   height, 
									   8, 
									   24, 
									   pict.linesize[0], 
									   colorSpace, 
									   bitmapInfo, 
									   provider, 
									   NULL, 
									   NO, 
									   kCGRenderingIntentDefault);
	CGColorSpaceRelease(colorSpace);
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	CGDataProviderRelease(provider);
	CFRelease(data);
	
	return image;
}

-(void)savePPMPicture:(AVPicture)pict width:(int)width height:(int)height index:(int)iFrame {
    FILE *pFile;
	NSString *fileName;
    int  y;
	
	fileName = [Utilities documentsPath:[NSString stringWithFormat:@"image%04d.ppm",iFrame]];
    // Open file
    NSLog(@"write image file: %@",fileName);
    pFile=fopen([fileName cStringUsingEncoding:NSASCIIStringEncoding], "wb");
    if(pFile==NULL)
        return;
	
    // Write header
    fprintf(pFile, "P6\n%d %d\n255\n", width, height);
	
    // Write pixel data
    for(y=0; y<height; y++)
        fwrite(pict.data[0]+y*pict.linesize[0], 1, width*3, pFile);
	
    // Close file
    fclose(pFile);
}

@end

//
//  ViewController.m
//  AVAssetWriter
//
//  Created by 李晓杰 on 2020/3/12.
//  Copyright © 2020 李晓杰. All rights reserved.
//

#import "ViewController.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CVPixelBuffer.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *audioPath = [[NSBundle mainBundle] pathForResource:@"12313.mp3" ofType:nil];
        NSString *videoPath = [[NSBundle mainBundle] pathForResource:@"你给我听好.mp4" ofType:nil];
        
        [self mergeVideo:videoPath audio:audioPath destFilePath:nil finish:^(NSString *str, NSError *err) {
            if (err) {
                NSLog(@"mergeVideo error \n%@", err.localizedDescription);
            }
            else {
                NSLog(@"合成完成");
            }
        }];
    });
}

- (void)mergeVideo:(NSString *)videoPath audio:(NSString *)audioPath destFilePath:(nonnull NSString *)destFilePath finish:(void (^)(NSString *, NSError *))finish
{
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    if (!videoPath || !audioPath || ![fileMgr fileExistsAtPath:videoPath] || ![fileMgr fileExistsAtPath:audioPath]) {
        if (finish) {
            NSError *error = [NSError errorWithDomain:@"ttlx_videoutil_error_domain" code:-1 userInfo:@{NSLocalizedDescriptionKey : @"视频或者音频文件不存在"}];
            finish(nil, error);
        }
        return;
    }

    AVAsset *videoAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:videoPath]];
    AVAsset *audioAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:audioPath]];
    
    NSError *error = nil;
    AVAssetReader *videoReader = [AVAssetReader assetReaderWithAsset:videoAsset error:&error];
    if (error) {
        if (finish) {
            finish(nil, error);
        }
        return;
    }

    AVAssetReader *audioReader = [AVAssetReader assetReaderWithAsset:audioAsset error:&error];
    if (error) {
        if (finish) {
            finish(nil, error);
        }
        return;
    }
    
    AVAssetReaderAudioMixOutput *audioOutput = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:[audioAsset tracksWithMediaType:AVMediaTypeAudio] audioSettings:nil];
    
    NSDictionary *videoOutputSetting = @{
         (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_422YpCbCr8]
       };
       
    AVAssetReaderTrackOutput *videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[videoAsset tracksWithMediaType:AVMediaTypeVideo].firstObject
                                                                                       outputSettings:videoOutputSetting
                                             ];
    
    if([videoReader canAddOutput:videoOutput]) {
        [videoReader addOutput:videoOutput];
    }
    else {
        NSLog(@"添加videoOutput失败");
        if(finish) {
            finish(nil, [NSError errorWithDomain:@"ttlx_videoutil_error_domain" code:-1 userInfo:@{NSLocalizedFailureReasonErrorKey : @"添加videoOutput失败"}]);
        }
        return;
    }


    if([audioReader canAddOutput:audioOutput]) {
        [audioReader addOutput:audioOutput];
    }
    else {
        NSLog(@"添加audioOutput失败");
        if(finish) {
            finish(nil, [NSError errorWithDomain:@"ttlx_videoutil_error_domain" code:-1 userInfo:@{NSLocalizedFailureReasonErrorKey : @"添加audioOutput失败"}]);
        }
        return;
    }
    
    
    if (!destFilePath) {
        destFilePath = [[self getTempDirectory] stringByAppendingString:@"/replay_merger.mp4"];
    }
    if ([fileMgr fileExistsAtPath:destFilePath]) {
        [fileMgr removeItemAtPath:destFilePath error:nil];
    }

    NSDictionary *audioInputSetting = @{ AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                         AVSampleRateKey : @(16000),
                                         AVNumberOfChannelsKey : @1,
//                                         AVLinearPCMBitDepthKey : @16,
//                                         AVLinearPCMIsNonInterleaved : @(NO),
//                                         AVLinearPCMIsFloatKey : @(NO),
//                                         AVLinearPCMIsBigEndianKey : @(NO),

    };

    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:destFilePath] fileType:AVFileTypeMPEG4 error:&error];
    AVAssetWriterInput *audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioInputSetting];
    AVAssetWriterInput *videoInput = [self videoInput];

    if ([writer canAddInput:videoInput]) {
        [writer addInput:videoInput];
    }
    else {
        NSLog(@"添加videoInput失败");
        if(finish) {
            finish(nil, [NSError errorWithDomain:@"ttlx_videoutil_error_domain" code:-1 userInfo:@{NSLocalizedFailureReasonErrorKey : @"添加videoInput失败"}]);
        }
        return;
    }
    
    if ([writer canAddInput:audioInput]) {
        [writer addInput:audioInput];
    }
    else {
        NSLog(@"添加audioInput失败");
        if(finish) {
            finish(nil, [NSError errorWithDomain:@"ttlx_videoutil_error_domain" code:-1 userInfo:@{NSLocalizedFailureReasonErrorKey : @"添加audioInput失败"}]);
        }
        return;
    }

    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];


    [audioReader startReading];
    [videoReader startReading];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [audioInput requestMediaDataWhenReadyOnQueue:dispatch_queue_create("video_util_audio_input", DISPATCH_QUEUE_SERIAL) usingBlock:^{
        if ([audioInput isReadyForMoreMediaData]) {
            CMSampleBufferRef ref = [audioOutput copyNextSampleBuffer];

            if (ref != NULL) {
                if (![audioInput appendSampleBuffer:ref]) {
                    [audioReader cancelReading];
                    [audioInput markAsFinished];

                    NSAssert(NO, @"audio append 失败");
//
                    NSLog(@"%ld, %@", (long)writer.status, writer.error.localizedDescription);
                }

                CFRelease(ref);
            }
            else {
                [audioReader cancelReading];
                [audioInput markAsFinished];

                if (audioReader.status != AVAssetReaderStatusReading) {
                    dispatch_semaphore_signal(semaphore);
//                    [writer finishWritingWithCompletionHandler: ^{
//
//                    }];
                }
                else {
                   dispatch_semaphore_signal(semaphore);
                }

                NSLog(@"audio 读取完成 %@ ", destFilePath);
            }
        }
    }];

    [videoInput requestMediaDataWhenReadyOnQueue:dispatch_queue_create("video_util_video_input", DISPATCH_QUEUE_SERIAL) usingBlock:^{
        if ([videoInput isReadyForMoreMediaData]) {
            CMSampleBufferRef ref = [videoOutput copyNextSampleBuffer];

            if (ref != NULL) {
                BOOL resu = [videoInput appendSampleBuffer:ref];
                if (!resu) {
                    [videoReader cancelReading];
                    [videoInput markAsFinished];
                    NSAssert(NO, @"video append 失败");
                    NSLog(@"%ld, %@", (long)writer.status, writer.error.localizedDescription);
                }

                CFRelease(ref);
            }
            else {
                [videoReader cancelReading];
                [videoInput markAsFinished];

                if (videoReader.status != AVAssetReaderStatusReading) {
                    dispatch_semaphore_signal(semaphore);
                }
                else {
                    dispatch_semaphore_signal(semaphore);
                }

                NSLog(@"video 读取完成 %@ ", destFilePath);
            }
        }
    }];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (int i = 0; i < 2; i++) {
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        }

        [writer finishWritingWithCompletionHandler:^{
            if (finish) {
                finish(destFilePath, nil);
            }
        }];
    });
}


- (AVAssetWriterInput *)videoInput
{
    
    NSDictionary *videoSettings = @{
        AVVideoCompressionPropertiesKey : @ {
        AVVideoAverageBitRateKey: @2000000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
        },
        AVVideoCodecKey                 : AVVideoCodecTypeH264,
        AVVideoWidthKey                 : [NSNumber numberWithFloat:[UIScreen mainScreen].bounds.size.height],
        AVVideoHeightKey                : [NSNumber numberWithFloat:[UIScreen mainScreen].bounds.size.width]
    };
    
    AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    videoInput.expectsMediaDataInRealTime = YES;
    return videoInput;
}

- (NSDictionary *)audioSettingDict
{
    NSDictionary *audioInputSetting = @{ AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                         AVSampleRateKey : @(44100),
                                         AVNumberOfChannelsKey : @1,
                                         
    };
    
    
    return audioInputSetting;
}


- (NSString *)getTempDirectory
{
    NSString *ttlxDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];

    return ttlxDir;
//    return NSTemporaryDirectory();
}
@end

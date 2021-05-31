//
//  ViewController.m
//  XDXPCMToAACDemo
//
//  Created by demon on 23/03/2017.
//
//

#import "ViewController.h"
#import "XDXRecoder.h"
#import <AVFoundation/AVFoundation.h>
#import "XDXVolumeView.h"

#define kScreenWidth [UIScreen mainScreen].bounds.size.width
#define kScreenHeight [UIScreen mainScreen].bounds.size.height


@interface ViewController ()

@property (nonatomic, strong) XDXRecorder    *liveRecorder;
@property (nonatomic, strong) XDXVolumeView  *recordVolumeView;
@property (nonatomic, assign) BOOL              isActive;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self configureAudio];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAudioSessionEvent:) name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioServerReset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
    /*
        注意，本例中XDXRecorder中分别用AudioQueue与AudioUnit实现了录音，区别好处在博客简书中均有介绍，在此不再重复，请根据需要选择。
     */
    
    self.liveRecorder = [[XDXRecorder alloc] init];
    
#warning You need select use Audio Unit or Audio Queue
    //使用audioqueue
    self.liveRecorder.releaseMethod = XDXRecorderReleaseMethodAudioQueue;
    
    [self initVoumeView];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)configureAudio
{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    BOOL success;
    NSError* error = nil;
    
    //AVAudioSessionCategoryOptionAllowBluetoothA2DP 可以使用蓝牙声音输出
    //AVAudioSessionCategoryOptionDefaultToSpeaker 不要用它，否则所有声音会直接从喇叭播放
    //当需要从喇叭播放时请使用audioSession overrideOutputAudioPort:<#(AVAudioSessionPortOverride)#> error:<#(NSError * _Nullable * _Nullable)#>
    
    success = [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetoothA2DP|AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionMixWithOthers error:&error];
    

    if(!success)
        NSLog(@"AVAudioSession error setCategory = %@",error.debugDescription);

    
    success = [audioSession setActive:YES error:&error];
    if (success){
        self.isActive = TRUE;
        //使用内置麦克风
        [self useBestAudioOutput];
        [self useBuiltInMic];
    }

}

- (void)useBestAudioOutput{
    if (!self.isActive){
        return;
    }

    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    AVAudioSessionPortDescription *currentOutput = [[currentRoute outputs] firstObject];
    int outputCount = [[currentRoute outputs] count];
    if ((outputCount > 1) && [currentOutput.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker]){
        //当前使用喇叭输出
        //如果需要，使用默认输出
        NSLog(@"set to default output");
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    }else if ((outputCount > 1) && [currentOutput.portType isEqualToString:AVAudioSessionPortBuiltInReceiver]){
        //当前使用听筒输出
        //如果需要，使用强制喇叭输出
        if (outputCount > 2){
            //当前有更多的输出设备，当前没有使用喇叭输出
        }else{
            NSLog(@"set to seapker output");
            [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
        }
        
    }else if (outputCount > 2){
        //当前有更多的输出设备，当前没有使用喇叭输出
        //如果需要，使用强制喇叭输出
//        NSLog(@"set to seapker output");
//        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    }

}

- (void)useBuiltInMic{
    if (!self.isActive){
        return;
    }
    NSError* error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    AVAudioSessionPortDescription *currentInput = [[currentRoute inputs] firstObject];
    if ([currentInput.portType isEqualToString:AVAudioSessionPortBuiltInMic]){
        AVAudioSessionDataSourceDescription* source = [currentInput.dataSources firstObject];
        NSString* polar = [source selectedPolarPattern];
        if (currentInput.selectedDataSource == source && [polar isEqualToString:AVAudioSessionPolarPatternOmnidirectional]){
            return;//不需要做任何设置
        }
    }
    NSLog(@"use built in mic");
    for (AVAudioSessionPortDescription *inputPort in [audioSession availableInputs])
    {
        if([inputPort.portType isEqualToString:AVAudioSessionPortBuiltInMic])
        {
            [audioSession setPreferredInput:inputPort error:&error];
            if (error){
                NSLog(@"AVAudioSession error setPreferredInput = %@",error.debugDescription);
            }
            //我们只用最安全的第一个data source和全向 polar
            for (AVAudioSessionDataSourceDescription* source in [inputPort dataSources]){
                
                [inputPort setPreferredDataSource:source error:&error];
                if (error){
                    NSLog(@"AVAudioSession error setPreferredDataSource = %@",error.debugDescription);
                }
                
                [source setPreferredPolarPattern:AVAudioSessionPolarPatternOmnidirectional
                                           error:&error];
                if (error){
                    NSLog(@"AVAudioSession error setPreferredPolarPattern = %@",error.debugDescription);
                }
                break;
            }
            [audioSession setPreferredIOBufferDuration:0.01 error:&error]; // 10ms采集一次
            if (error){
                NSLog(@"AVAudioSession error setPreferredIOBufferDuration = %@",error.debugDescription);
            }
            //此选项确保可以录到所有的频谱
            [audioSession setPreferredSampleRate:48000 error:&error];
            if (error){
                NSLog(@"AVAudioSession error setPreferredSampleRate = %@",error.debugDescription);
            }
            //内置麦克风只有单声道
            [audioSession setPreferredInputNumberOfChannels:1 error:&error];
            if (error){
                NSLog(@"AVAudioSession error setPreferredInputNumberOfChannels = %@",error.debugDescription);
            }
            break;
        }
    }
}

- (void) refreshAudioSource: (NSNotification *) notification{
    [self useBestAudioOutput];
    [self useBuiltInMic];
}

- (void) audioServerReset: (NSNotification *) notification{
    [self endAudio:nil];
    [self performSelector:@selector(configureAudio) withObject:nil afterDelay:0.1];
}

- (void) onAudioSessionEvent: (NSNotification *) notification
{
    //Check the type of notification, especially if you are sending multiple AVAudioSession events here
    NSLog(@"Interruption notification name %@", notification.name);
    NSError* error = nil;
    if ([notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        NSLog(@"Interruption notification received %@!", notification);
        
        //Check to see if it was a Begin interruption
        if ([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeBegan]]) {
            NSLog(@"Interruption began!");
            AVAudioSession *audioSession = [AVAudioSession sharedInstance];
            [audioSession setActive:FALSE error:&error];
            if (!error){
                self.isActive = FALSE;
                NSLog(@"audio session is deactive");
                [self endAudio:nil];
            }
            
        } else if([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeEnded]]){
            NSLog(@"Interruption ended!");

            [self performSelector:@selector(configureAudio) withObject:notification afterDelay:0.1];
        }
    }
}


- (void)audioRouteChanged:(NSNotification*)notify {
    NSDictionary *dic = notify.userInfo;
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    AVAudioSessionRouteDescription *oldRoute = [dic objectForKey:AVAudioSessionRouteChangePreviousRouteKey];
    
    AVAudioSessionPortDescription* currentInput = [currentRoute.inputs firstObject];
    AVAudioSessionPortDescription* currentOutput = [currentRoute.outputs firstObject];
    
    AVAudioSessionPortDescription* oldInput = [oldRoute.inputs firstObject];
    AVAudioSessionPortDescription* oldOutput = [oldRoute.outputs firstObject];
    
    NSNumber *routeChangeReason = [dic objectForKey:AVAudioSessionRouteChangeReasonKey];

    int reason = [routeChangeReason intValue];
    NSLog(@"audio route changed: reason: %@\n input:\n|old|%@,\n|new|%@,\n output:\n|old|%@,\n|new|%@",routeChangeReason,[oldInput debugDescription],[currentInput debugDescription],[oldOutput debugDescription],[currentOutput debugDescription]);
    //每次有变化时根据当前程序的设置需要重新更改一下
    if (reason == AVAudioSessionRouteChangeReasonNewDeviceAvailable || reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable ||
        reason == AVAudioSessionRouteChangeReasonWakeFromSleep || reason == AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory){
        [self performSelector:@selector(configureAudio) withObject:notify afterDelay:0.1];
    }
    
}


- (IBAction)startAudio:(id)sender {
    if (self.liveRecorder.releaseMethod == XDXRecorderReleaseMethodAudioUnit) {
        [self.liveRecorder startAudioUnitRecorder];
    }else if (self.liveRecorder.releaseMethod == XDXRecorderReleaseMethodAudioQueue) {
        [self.liveRecorder startAudioQueueRecorder];
    }
}

- (IBAction)endAudio:(id)sender {
    if (self.liveRecorder.releaseMethod == XDXRecorderReleaseMethodAudioUnit) {
        [self.liveRecorder stopAudioUnitRecorder];
    }else if (self.liveRecorder.releaseMethod == XDXRecorderReleaseMethodAudioQueue) {
        [self.liveRecorder stopAudioQueueRecorder];
    }
}

#pragma mark - Volume
- (void)initVoumeView {
    CGFloat volumeHeight    = 5;
    CGFloat dockViewWidth   = 394;
    CGFloat volumeX         = (kScreenWidth - dockViewWidth) / 2;
    self.recordVolumeView   = [[XDXVolumeView alloc] initWithFrame:CGRectMake(0, kScreenHeight - volumeHeight, kScreenWidth, volumeHeight)];
    
    [self.view addSubview:self.recordVolumeView];
    
    [NSTimer scheduledTimerWithTimeInterval:0.25f target:self selector:@selector(updateVolume) userInfo:nil repeats:YES];
}

-(void)updateVolume {
    
    CGFloat volumeRecord = self.liveRecorder.volLDB;
    
    if(volumeRecord >= -40 && volumeRecord <= 0) {
        volumeRecord = volumeRecord + 40;
    } else if(volumeRecord > 0) {
        volumeRecord = 40;
    } else {
        volumeRecord = 0;
    }
    
//    log4cplus_debug("Volume View","volumeRecord is %f, volumeR is %f",volumeRecord, volumePlay);
    [self.recordVolumeView setCurrentVolumn:volumeRecord    isRecord:YES];
}

@end

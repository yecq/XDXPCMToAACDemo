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
#import "JSToastDialogs.h"

#define kScreenWidth [UIScreen mainScreen].bounds.size.width
#define kScreenHeight [UIScreen mainScreen].bounds.size.height

typedef enum : NSUInteger {
    DEFAULT_MIC,
    BUILTIN_MIC,
    HEADSET_MIC,
} MIC_TYPES;

@interface ViewController ()

@property (nonatomic, strong) XDXRecorder    *liveRecorder;
@property (nonatomic, strong) XDXVolumeView  *recordVolumeView;
@property (nonatomic, assign) BOOL              isActive;
@property (nonatomic, assign) MIC_TYPES         selectMicSource; //0 default    1 builtinmic      2 headsetmic
@property (nonatomic, assign) BOOL              forceSpeaker; //是否想要强制用喇叭输出
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.selectMicSource = DEFAULT_MIC;
    self.forceSpeaker = FALSE;
    // Do any additional setup after loading the view, typically from a nib.
   
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAudioSessionEvent:) name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioServerReset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
    
    [self configureAudio];
    
    
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

- (IBAction)setDefault:(id)sender {
    self.selectMicSource = DEFAULT_MIC;
    [self configureAudio];
}

- (IBAction)setBuiltInMic:(id)sender {
    self.selectMicSource = BUILTIN_MIC;
    [self configureAudio];
}

- (IBAction)setHeadsetMic:(id)sender {
    self.selectMicSource = HEADSET_MIC;
    [self configureAudio];
}

- (IBAction)switchForceSpeaker:(id)sender {
    self.forceSpeaker = !self.forceSpeaker;
    [self configureAudio];
}

-(BOOL)needSetCategory{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    AVAudioSessionCategoryOptions options;
    NSString* mode;
    if (self.selectMicSource == DEFAULT_MIC){
        //default,用系统默认，允许蓝牙耳机录音
        options = AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionAllowBluetoothA2DP|AVAudioSessionCategoryOptionMixWithOthers;
        mode = AVAudioSessionModeDefault;
    }else{
        //另外两种不允许蓝牙耳机录音
        options = AVAudioSessionCategoryOptionAllowBluetoothA2DP|AVAudioSessionCategoryOptionMixWithOthers;
        mode = AVAudioSessionModeVideoRecording;//这个选项正好，但是AVCaptureSession会修改AVAudioSession属性
    }
    if (![audioSession.category isEqualToString:AVAudioSessionCategoryPlayAndRecord] ||
        audioSession.categoryOptions != options || ![audioSession.mode isEqualToString:mode])
        return TRUE;
    
    return FALSE;
}

-(void)configureAudio
{
//    [[JSToastDialogs shareInstance] makeToast:@"configureAudio" duration:1.0];
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    BOOL success = FALSE;
    NSError* error = nil;
    
    //AVCaptureSession或其它代码会修改我们的选项，所以每次启动录音前都要根据当前的录音context重新设置audioSession
    //AVAudioSessionCategoryOptionAllowBluetoothA2DP 可以使用蓝牙声音输出
    //AVAudioSessionCategoryOptionAllowBluetooth 除非一定需要从蓝牙耳机录音，否则不要加上，airpods会把手机麦克风选项排除
    //AVAudioSessionCategoryOptionDefaultToSpeaker 不要用它，否则所有声音会直接从喇叭播放
    //当需要从喇叭播放时请使用audioSession overrideOutputAudioPort:<#(AVAudioSessionPortOverride)#> error:<#(NSError * _Nullable * _Nullable)#>
    AVAudioSessionCategoryOptions options;
    NSString* mode;
    if (self.selectMicSource == DEFAULT_MIC){
        //default,用系统默认，允许蓝牙耳机录音
        options = AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionAllowBluetoothA2DP|AVAudioSessionCategoryOptionMixWithOthers;
        mode = AVAudioSessionModeDefault;
    }else{
        //另外两种不允许蓝牙耳机录音
        options = AVAudioSessionCategoryOptionAllowBluetoothA2DP|AVAudioSessionCategoryOptionMixWithOthers;
        mode = AVAudioSessionModeVideoRecording;//这个选项正好，但是AVCaptureSession会修改AVAudioSession属性
    }
    if (![audioSession.category isEqualToString:AVAudioSessionCategoryPlayAndRecord] || audioSession.categoryOptions != options){
        success = [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:options error:&error];
        if(!success){
            self.isActive = FALSE;
            NSLog(@"AVAudioSession error setCategory = %@",error.debugDescription);
            return;
        }
    }

    if (![audioSession.mode isEqualToString:mode]){
        [audioSession setMode:mode error:&error];
        if (error){
            self.isActive = FALSE;
            NSLog(@"AVAudioSession error setMode = %@",error.debugDescription);
            return;
        }
    }

    success = [audioSession setActive:YES error:&error];
    if (success){
        if (!self.isActive){
            NSLog(@"AVAudioSession become active");
            self.isActive = TRUE;
        }
        [self refreshAudioSource:nil];
    }else{
        NSLog(@"AVAudioSession error setActive = %@",error.debugDescription);
        self.isActive = FALSE;
    }
}

- (void)useBestAudioOutput{
    if (!self.isActive){
        return;
    }
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    AVAudioSessionPortDescription *currentOutput = [[currentRoute outputs] firstObject];
    if (self.forceSpeaker && ![currentOutput.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker]){
        NSLog(@"set to speaker output");
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    }else if (!self.forceSpeaker){
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    }
}

- (void) refreshAudioSource: (NSNotification *) notification{
    NSLog(@"refreshAudioSource");
//    [[JSToastDialogs shareInstance] makeToast:@"refreshAudioSource" duration:1.0];
    [self useBestAudioOutput];
    if (self.selectMicSource == BUILTIN_MIC){
        [self useBuiltInMic];
    }else if (self.selectMicSource == HEADSET_MIC){
        [self useHeadsetMic];
    }else{
        if ([AVAudioSession sharedInstance].preferredInput != nil){
            //clear prefererd input if we use default
            [[AVAudioSession sharedInstance] setPreferredInput:nil error:nil];
        }
        
        [self setDefaultMicParams];
    }
}

- (BOOL)needSetDefaultMicParams{
    if (!self.isActive){
        return FALSE;
    }
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    if (audioSession.preferredSampleRate != 48000 ||
        audioSession.preferredInputNumberOfChannels != 1){
        NSLog(@"audioSession.preferredSampleRate:%f\naudioSession.preferredInputNumberOfChannels:%ld",audioSession.preferredSampleRate,(long)audioSession.preferredInputNumberOfChannels);
        return TRUE;
    }
    return FALSE;
}

- (void)setDefaultMicParams{
    if (!self.isActive){
        return;
    }
    NSError* error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    //此选项确保可以录到所有的频谱，小程序可以用当前录音参数中的samplerate来替代
    if (audioSession.preferredSampleRate != 48000){
        [audioSession setPreferredSampleRate:48000 error:&error];
        if (error){
            NSLog(@"AVAudioSession error setPreferredSampleRate = %@",error.debugDescription);
        }
    }
    
    //内置麦克风只有单声道
    if (audioSession.preferredInputNumberOfChannels != 1){
        [audioSession setPreferredInputNumberOfChannels:1 error:&error];
        if (error){
            NSLog(@"AVAudioSession error setPreferredInputNumberOfChannels = %@",error.debugDescription);
        }
    }
}

- (BOOL)needSetMic: (NSArray *) inputs{
    if (!self.isActive){
        return FALSE;
    }
    AVAudioSession* session = [AVAudioSession sharedInstance];
    AVAudioSessionPortDescription *currentInput = [inputs firstObject];

    if (self.selectMicSource == DEFAULT_MIC){
        //we need to clear preferred input
        if (session.preferredInput != nil){
            return TRUE;
        }
        return FALSE;
    }else if (self.selectMicSource == BUILTIN_MIC){
        //if builtin mic is already used, check params
        if ([currentInput.portType isEqualToString:AVAudioSessionPortBuiltInMic]){
            AVAudioSessionDataSourceDescription* source = [currentInput.dataSources firstObject];
            NSString* polar = [source selectedPolarPattern];
            if ((currentInput.selectedDataSource.dataSourceID == source.dataSourceID) && [polar isEqualToString:AVAudioSessionPolarPatternOmnidirectional]){
                return FALSE;
            }else{
                return TRUE;
            }
        }
        //we need to set preferred input
        if (session.preferredInput != nil && ![session.preferredInput.portType isEqualToString:AVAudioSessionPortBuiltInMic]){
            return TRUE;
        }
    }else if (self.selectMicSource == HEADSET_MIC){
        if (self.forceSpeaker){
            return FALSE;//don't try to change input if we use overrideOutput
        }
        if ([currentInput.portType isEqualToString:AVAudioSessionPortHeadsetMic]){
            return FALSE;
        }
        //we need to set preferred input
        if (session.preferredInput != nil && ![session.preferredInput.portType isEqualToString:AVAudioSessionPortHeadsetMic]){
            return TRUE;
        }
    }
    if ([[session availableInputs] count] > 1){
        return TRUE; //if there is more choice, let's try
    }
    return FALSE;
}

- (void)useBuiltInMic{
    if (!self.isActive){
        return;
    }
    BOOL needSetMic = TRUE;
    NSError* error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    AVAudioSessionPortDescription *currentInput = [[currentRoute inputs] firstObject];
    if ([currentInput.portType isEqualToString:AVAudioSessionPortBuiltInMic]){
        AVAudioSessionDataSourceDescription* source = [currentInput.dataSources firstObject];
        NSString* polar = [source selectedPolarPattern];
        if ([currentInput.selectedDataSource dataSourceID] == [source dataSourceID] && [polar isEqualToString:AVAudioSessionPolarPatternOmnidirectional]){
            needSetMic = FALSE;//不需要做任何设置
        }
    }
    if (needSetMic){
//        [[JSToastDialogs shareInstance] makeToast:@"use built in mic" duration:1.0];
        NSLog(@"use built in mic");
        for (AVAudioSessionPortDescription *inputPort in [audioSession availableInputs])
        {
            if([inputPort.portType isEqualToString:AVAudioSessionPortBuiltInMic])
            {
                if (audioSession.preferredInput == nil || ![audioSession.preferredInput.portType isEqualToString:AVAudioSessionPortBuiltInMic]){
                    [audioSession setPreferredInput:inputPort error:&error];
                    if (error){
                        NSLog(@"AVAudioSession error setPreferredInput = %@",error.debugDescription);
                    }
                }
               
                //我们只用最安全的第一个data source和全向 polar
                for (AVAudioSessionDataSourceDescription* source in [inputPort dataSources]){
                    if (inputPort.preferredDataSource == nil || [inputPort.preferredDataSource dataSourceID] != [source dataSourceID]){
                        [inputPort setPreferredDataSource:source error:&error];
                        if (error){
                            NSLog(@"AVAudioSession error setPreferredDataSource = %@",error.debugDescription);
                        }
                    }

                    if (![[source preferredPolarPattern] isEqualToString:AVAudioSessionPolarPatternOmnidirectional]){
                        [source setPreferredPolarPattern:AVAudioSessionPolarPatternOmnidirectional
                                                   error:&error];
                        
                        if (error){
                            NSLog(@"AVAudioSession error setPreferredPolarPattern = %@",error.debugDescription);
                        }
                    }

                    break;
                }
                
                break;
            }
        }
        //clear if prefered input is not right
        if (audioSession.preferredInput != nil && ![audioSession.preferredInput.portType isEqualToString:AVAudioSessionPortBuiltInMic]){
            [audioSession setPreferredInput:nil error:&error];
            if (error){
                NSLog(@"AVAudioSession error setPreferredInput = %@",error.debugDescription);
            }
        }
    }
    [self setDefaultMicParams];
}

- (void)useHeadsetMic{
    if (!self.isActive){
        return;
    }
    BOOL needSetMic = TRUE;
    NSError* error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    AVAudioSessionPortDescription *currentInput = [[currentRoute inputs] firstObject];
    if (self.forceSpeaker || [currentInput.portType isEqualToString:AVAudioSessionPortHeadsetMic]){
        needSetMic = FALSE;//如果当前已经在用耳机或是强制输出喇叭，就不要做任何设置
    }
    if (needSetMic){
        NSLog(@"use headset mic");
        for (AVAudioSessionPortDescription *inputPort in [audioSession availableInputs])
        {
            if([inputPort.portType isEqualToString:AVAudioSessionPortHeadsetMic])
            {
                if (audioSession.preferredInput == nil || ![audioSession.preferredInput.portType isEqualToString:AVAudioSessionPortHeadsetMic]){
                    [audioSession setPreferredInput:inputPort error:&error];
                    if (error){
                        NSLog(@"AVAudioSession error setPreferredInput = %@",error.debugDescription);
                    }
                }
                
                break;
            }
        }
        //clear if prefered input is not right
        if (audioSession.preferredInput != nil && ![audioSession.preferredInput.portType isEqualToString:AVAudioSessionPortHeadsetMic]){
            [audioSession setPreferredInput:nil error:&error];
            if (error){
                NSLog(@"AVAudioSession error setPreferredInput = %@",error.debugDescription);
            }
        }
    }
    [self setDefaultMicParams];
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
    
    NSArray* inputs = currentRoute.inputs;
    
    AVAudioSessionPortDescription* currentInput = [currentRoute.inputs firstObject];
    AVAudioSessionPortDescription* currentOutput = [currentRoute.outputs firstObject];
    
    AVAudioSessionPortDescription* oldInput = [oldRoute.inputs firstObject];
    AVAudioSessionPortDescription* oldOutput = [oldRoute.outputs firstObject];
    
    NSNumber *routeChangeReason = [dic objectForKey:AVAudioSessionRouteChangeReasonKey];

    int reason = [routeChangeReason intValue];
    
    NSString* msg = [NSString stringWithFormat:@"audio route changed: reason: %@\n input:\n|old|%@,\n|new|%@,\n output:\n|old|%@,\n|new|%@",routeChangeReason,[oldInput debugDescription],[currentInput debugDescription],[oldOutput debugDescription],[currentOutput debugDescription]];
//    NSString* msg = [NSString stringWithFormat:@"%@", [[AVAudioSession sharedInstance].availableInputs debugDescription]];
    [[JSToastDialogs shareInstance] makeToast:msg duration:5.0];
    NSLog(@"audio route changed: reason: %@\n input:\n|old|%@,\n|new|%@,\n output:\n|old|%@,\n|new|%@",routeChangeReason,[oldInput debugDescription],[currentInput debugDescription],[oldOutput debugDescription],[currentOutput debugDescription]);
    //每次有变化时根据当前程序的设置需要重新更改一下
    if (reason == AVAudioSessionRouteChangeReasonNewDeviceAvailable || reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable ||
        reason == AVAudioSessionRouteChangeReasonWakeFromSleep || reason == AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory){
        [self performSelector:@selector(configureAudio) withObject:notify afterDelay:0.1];
    }else if ((self.forceSpeaker && currentOutput != nil && ![currentOutput.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker])
              || [self needSetCategory] ||[self needSetMic:inputs] || [self needSetDefaultMicParams]){
        //如果当前的输入输出与预期的不符合或者参数不符合的也要重新更改一下
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

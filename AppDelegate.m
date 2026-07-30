#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <IOBluetooth/IOBluetooth.h>
#import <IOBluetooth/objc/IOBluetoothHandsFree.h>
#import <IOBluetooth/objc/IOBluetoothHandsFreeAudioGateway.h>

static OSStatus KeepAliveIOProc(AudioObjectID inDevice,
                                const AudioTimeStamp *inNow,
                                const AudioBufferList *inInputData,
                                const AudioTimeStamp *inInputTime,
                                AudioBufferList *outOutputData,
                                const AudioTimeStamp *inOutputTime,
                                void *inClientData) {
    if (outOutputData) {
        for (UInt32 i = 0; i < outOutputData->mNumberBuffers; i++) {
            AudioBuffer buffer = outOutputData->mBuffers[i];
            if (buffer.mData && buffer.mDataByteSize) memset(buffer.mData, 0, buffer.mDataByteSize);
        }
    }
    return noErr;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, IOBluetoothHandsFreeAudioGatewayDelegate> {
    AudioDeviceIOProcID _keepAliveProc;
    AudioObjectID _keepAliveDevice;
    BOOL _keepAliveRunning;
}
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenu *menu;
@property(nonatomic, strong) NSMenuItem *statusMenuItem;
@property(nonatomic, strong) IOBluetoothDevice *mic;
@property(nonatomic, strong) IOBluetoothHandsFreeAudioGateway *gateway;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, copy) NSString *lowLatencyError;
@property(nonatomic, assign) BOOL permissionRequestInFlight;
@property(nonatomic, copy) AudioObjectPropertyListenerBlock outputDeviceListener;
@end

static NSString *AudioDeviceName(AudioObjectID deviceID) {
    CFStringRef name = NULL;
    UInt32 size = sizeof(name);
    AudioObjectPropertyAddress address = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &name) != noErr || !name) return nil;
    return CFBridgingRelease(name);
}

static BOOL AudioDeviceHasInput(AudioObjectID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreams,
        kAudioDevicePropertyScopeInput,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &size) != noErr) return NO;
    return size >= sizeof(AudioStreamID);
}

static BOOL AudioDeviceHasOutput(AudioObjectID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreams,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &size) != noErr) return NO;
    return size >= sizeof(AudioStreamID);
}

static NSString *AudioDeviceUID(AudioObjectID deviceID) {
    CFStringRef uid = NULL;
    UInt32 size = sizeof(uid);
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &uid) != noErr || !uid) return nil;
    return CFBridgingRelease(uid);
}

static AudioObjectID DefaultAudioDevice(AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectID deviceID = kAudioObjectUnknown;
    UInt32 size = sizeof(deviceID);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &deviceID) != noErr) {
        return kAudioObjectUnknown;
    }
    return deviceID;
}

static OSStatus SetDefaultAudioDevice(AudioObjectPropertySelector selector, AudioObjectID deviceID) {
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = sizeof(deviceID);
    return AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, size, &deviceID);
}

static AudioObjectID FindOutputDeviceByUID(NSString *wantedUID) {
    if (!wantedUID.length) return kAudioObjectUnknown;
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr) {
        return kAudioObjectUnknown;
    }
    AudioObjectID *devices = malloc(size);
    if (!devices) return kAudioObjectUnknown;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices) != noErr) {
        free(devices);
        return kAudioObjectUnknown;
    }
    AudioObjectID match = kAudioObjectUnknown;
    NSUInteger count = size / sizeof(AudioObjectID);
    for (NSUInteger i = 0; i < count; i++) {
        if (AudioDeviceHasOutput(devices[i]) && [AudioDeviceUID(devices[i]) isEqualToString:wantedUID]) {
            match = devices[i];
            break;
        }
    }
    free(devices);
    return match;
}

static UInt32 AudioDeviceTransportType(AudioObjectID deviceID) {
    UInt32 transport = 0;
    UInt32 size = sizeof(transport);
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyTransportType,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &transport);
    return transport;
}

static AudioObjectID FindInputDevice(NSString *wantedName) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr) {
        return kAudioObjectUnknown;
    }
    AudioObjectID *devices = malloc(size);
    if (!devices) return kAudioObjectUnknown;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices) != noErr) {
        free(devices);
        return kAudioObjectUnknown;
    }
    AudioObjectID match = kAudioObjectUnknown;
    NSUInteger count = size / sizeof(AudioObjectID);
    for (NSUInteger i = 0; i < count; i++) {
        NSString *name = AudioDeviceName(devices[i]);
        if (AudioDeviceHasInput(devices[i]) && [name isEqualToString:wantedName]) {
            match = devices[i];
            break;
        }
    }
    free(devices);
    return match;
}

@implementation AppDelegate

static NSString * const PreferredOutputUIDKey = @"PreferredOutputDeviceUID";
static NSString * const PreferredSystemOutputUIDKey = @"PreferredSystemOutputDeviceUID";

- (NSImage *)statusImageConnected:(BOOL)connected {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(24, 18)];
    [image lockFocus];
    NSImage *mic = [NSImage imageWithSystemSymbolName:(connected ? @"mic.fill" : @"mic.slash")
                             accessibilityDescription:@"DJI Mic 2 Bridge"];
    [mic drawInRect:NSMakeRect(0, 1, 16, 16)];
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:9],
        NSForegroundColorAttributeName: NSColor.labelColor
    };
    [@"D" drawAtPoint:NSMakePoint(15, 3) withAttributes:attributes];
    [image unlockFocus];
    image.template = YES;
    return image;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [self statusImageConnected:NO];
    self.statusItem.button.toolTip = @"DJI Mic 2 Bridge";

    self.menu = [NSMenu new];
    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"正在检查…" action:nil keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [self.menu addItem:self.statusMenuItem];
    [self.menu addItem:NSMenuItem.separatorItem];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:@"连接 / 重连 DJI Mic 2" action:@selector(connectMic:) keyEquivalent:@"r"]];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:@"设为系统默认输入" action:@selector(makeDefaultInput:) keyEquivalent:@"d"]];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:@"打开声音设置…" action:@selector(openSoundSettings:) keyEquivalent:@","]];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:@"断开音频链路" action:@selector(disconnectMic:) keyEquivalent:@""]];
    [self.menu addItem:NSMenuItem.separatorItem];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:@"退出 DJI Mic 2 Bridge" action:@selector(quit:) keyEquivalent:@"q"]];
    for (NSMenuItem *item in self.menu.itemArray) item.target = self;
    self.statusItem.menu = self.menu;

    self.mic = [self findPairedMic];
    [self rememberCurrentOutputsIfSafe];
    [self installOutputDeviceListeners];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshStatus:) userInfo:nil repeats:YES];
    [self refreshStatus:nil];
    [self performSelector:@selector(connectMic:) withObject:nil afterDelay:0.5];
}

- (IOBluetoothDevice *)findPairedMic {
    for (IOBluetoothDevice *device in IOBluetoothDevice.pairedDevices) {
        NSString *name = device.name.uppercaseString ?: @"";
        if ([name containsString:@"DJI"] && [name containsString:@"MIC"] && device.isHandsFreeDevice) return device;
    }
    return nil;
}

- (void)connectMic:(id)sender {
    self.lastError = nil;
    self.mic = [self findPairedMic];
    if (!self.mic) {
        self.lastError = @"未找到已配对的 DJI Mic 2";
        [self refreshStatus:nil];
        if (sender) [self showMessage:@"请先在“系统设置 → 蓝牙”中配对 DJI Mic 2，并让发射器保持蓝灯模式。"];
        return;
    }

    if (FindInputDevice(self.mic.name) != kAudioObjectUnknown) {
        [self restoreOutputsIfDJI];
        [self refreshStatus:nil];
        return;
    }

    [self rememberCurrentOutputsIfSafe];
    [self.gateway disconnect];
    self.gateway = [[IOBluetoothHandsFreeAudioGateway alloc] initWithDevice:self.mic delegate:self];
    self.gateway.supportedFeatures = IOBluetoothHandsFreeAudioGatewayFeatureCodecNegotiation;
    [self.gateway connect];
    [self refreshStatus:nil];
}

- (BOOL)isDJIAudioDevice:(AudioObjectID)deviceID {
    if (deviceID == kAudioObjectUnknown) return NO;
    NSString *name = AudioDeviceName(deviceID).uppercaseString ?: @"";
    NSString *pairedName = self.mic.name.uppercaseString;
    if (pairedName.length && [name isEqualToString:pairedName]) return YES;
    return [name containsString:@"DJI"] && [name containsString:@"MIC"];
}

- (AudioObjectID)fallbackOutputDevice {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr) {
        return kAudioObjectUnknown;
    }
    AudioObjectID *devices = malloc(size);
    if (!devices) return kAudioObjectUnknown;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices) != noErr) {
        free(devices);
        return kAudioObjectUnknown;
    }
    AudioObjectID firstNonDJI = kAudioObjectUnknown;
    AudioObjectID builtIn = kAudioObjectUnknown;
    NSUInteger count = size / sizeof(AudioObjectID);
    for (NSUInteger i = 0; i < count; i++) {
        if (!AudioDeviceHasOutput(devices[i]) || [self isDJIAudioDevice:devices[i]]) continue;
        if (firstNonDJI == kAudioObjectUnknown) firstNonDJI = devices[i];
        if (AudioDeviceTransportType(devices[i]) == kAudioDeviceTransportTypeBuiltIn) {
            builtIn = devices[i];
            break;
        }
    }
    free(devices);
    return builtIn != kAudioObjectUnknown ? builtIn : firstNonDJI;
}

- (void)rememberDevice:(AudioObjectID)deviceID forKey:(NSString *)key {
    if (deviceID == kAudioObjectUnknown || [self isDJIAudioDevice:deviceID] || !AudioDeviceHasOutput(deviceID)) return;
    NSString *uid = AudioDeviceUID(deviceID);
    if (uid.length) [NSUserDefaults.standardUserDefaults setObject:uid forKey:key];
}

- (void)rememberCurrentOutputsIfSafe {
    [self rememberDevice:DefaultAudioDevice(kAudioHardwarePropertyDefaultOutputDevice)
                  forKey:PreferredOutputUIDKey];
    [self rememberDevice:DefaultAudioDevice(kAudioHardwarePropertyDefaultSystemOutputDevice)
                  forKey:PreferredSystemOutputUIDKey];
}

- (void)restoreOutputSelector:(AudioObjectPropertySelector)selector preferenceKey:(NSString *)key {
    AudioObjectID current = DefaultAudioDevice(selector);
    if (current == kAudioObjectUnknown) return;
    if (![self isDJIAudioDevice:current]) {
        [self rememberDevice:current forKey:key];
        return;
    }

    NSString *savedUID = [NSUserDefaults.standardUserDefaults stringForKey:key];
    AudioObjectID target = FindOutputDeviceByUID(savedUID);
    if (target == kAudioObjectUnknown || [self isDJIAudioDevice:target]) target = [self fallbackOutputDevice];
    if (target != kAudioObjectUnknown && target != current) SetDefaultAudioDevice(selector, target);
}

- (void)restoreOutputsIfDJI {
    [self restoreOutputSelector:kAudioHardwarePropertyDefaultOutputDevice
                 preferenceKey:PreferredOutputUIDKey];
    [self restoreOutputSelector:kAudioHardwarePropertyDefaultSystemOutputDevice
                 preferenceKey:PreferredSystemOutputUIDKey];
}

- (void)installOutputDeviceListeners {
    if (self.outputDeviceListener) return;
    __weak typeof(self) weakSelf = self;
    self.outputDeviceListener = ^(UInt32 numberAddresses, const AudioObjectPropertyAddress *addresses) {
        [weakSelf restoreOutputsIfDJI];
    };
    AudioObjectPropertyAddress defaultOutputAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectPropertyAddress systemOutputAddress = {
        kAudioHardwarePropertyDefaultSystemOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &defaultOutputAddress,
                                        dispatch_get_main_queue(), self.outputDeviceListener);
    AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &systemOutputAddress,
                                        dispatch_get_main_queue(), self.outputDeviceListener);
}

- (void)removeOutputDeviceListeners {
    if (!self.outputDeviceListener) return;
    AudioObjectPropertyAddress defaultOutputAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectPropertyAddress systemOutputAddress = {
        kAudioHardwarePropertyDefaultSystemOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &defaultOutputAddress,
                                           dispatch_get_main_queue(), self.outputDeviceListener);
    AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &systemOutputAddress,
                                           dispatch_get_main_queue(), self.outputDeviceListener);
    self.outputDeviceListener = nil;
}

- (void)disconnectMic:(id)sender {
    [self stopLowLatencyKeepAlive];
    [self.gateway disconnect];
    self.gateway = nil;
    [self refreshStatus:nil];
}

- (void)startLowLatencyKeepAlive:(AudioObjectID)deviceID {
    if (_keepAliveRunning && _keepAliveDevice == deviceID) return;
    [self stopLowLatencyKeepAlive];

    _keepAliveDevice = deviceID;
    OSStatus status = AudioDeviceCreateIOProcID(deviceID, KeepAliveIOProc, (__bridge void *)self, &_keepAliveProc);
    if (status == noErr) status = AudioDeviceStart(deviceID, _keepAliveProc);
    if (status == noErr) {
        _keepAliveRunning = YES;
        self.lowLatencyError = nil;
    } else {
        if (_keepAliveProc) AudioDeviceDestroyIOProcID(deviceID, _keepAliveProc);
        _keepAliveProc = NULL;
        _keepAliveDevice = kAudioObjectUnknown;
        self.lowLatencyError = [NSString stringWithFormat:@"低延迟保活启动失败：%d", status];
    }
    [self refreshStatus:nil];
}

- (void)stopLowLatencyKeepAlive {
    if (_keepAliveProc && _keepAliveDevice != kAudioObjectUnknown) {
        if (_keepAliveRunning) AudioDeviceStop(_keepAliveDevice, _keepAliveProc);
        AudioDeviceDestroyIOProcID(_keepAliveDevice, _keepAliveProc);
    }
    _keepAliveProc = NULL;
    _keepAliveDevice = kAudioObjectUnknown;
    _keepAliveRunning = NO;
}

- (void)ensureLowLatencyKeepAlive:(AudioObjectID)deviceID {
    if (_keepAliveRunning && _keepAliveDevice == deviceID) return;
    AVAuthorizationStatus authorization = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (authorization == AVAuthorizationStatusAuthorized) {
        [self startLowLatencyKeepAlive:deviceID];
    } else if (authorization == AVAuthorizationStatusNotDetermined && !self.permissionRequestInFlight) {
        self.permissionRequestInFlight = YES;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.permissionRequestInFlight = NO;
                if (granted) {
                    [self startLowLatencyKeepAlive:deviceID];
                } else {
                    self.lowLatencyError = @"低延迟模式需要麦克风权限";
                    [self refreshStatus:nil];
                }
            });
        }];
    } else if (authorization == AVAuthorizationStatusDenied || authorization == AVAuthorizationStatusRestricted) {
        self.lowLatencyError = @"低延迟模式需要麦克风权限";
    }
}

- (void)makeDefaultInput:(id)sender {
    if (!self.mic) self.mic = [self findPairedMic];
    AudioObjectID deviceID = self.mic ? FindInputDevice(self.mic.name) : kAudioObjectUnknown;
    if (deviceID == kAudioObjectUnknown) {
        [self showMessage:@"DJI Mic 2 音频输入尚未就绪，请先点“连接 / 重连”。"];
        return;
    }
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = sizeof(deviceID);
    OSStatus status = AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, size, &deviceID);
    if (status != noErr) [self showMessage:[NSString stringWithFormat:@"无法设置默认输入（错误 %d）。", status]];
    [self refreshStatus:nil];
}

- (BOOL)isDefaultInput:(AudioObjectID)deviceID {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectID current = kAudioObjectUnknown;
    UInt32 size = sizeof(current);
    return AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &current) == noErr && current == deviceID;
}

- (void)refreshStatus:(id)sender {
    if (!self.mic) self.mic = [self findPairedMic];
    AudioObjectID deviceID = self.mic ? FindInputDevice(self.mic.name) : kAudioObjectUnknown;
    BOOL ready = deviceID != kAudioObjectUnknown;
    if (ready) {
        [self restoreOutputsIfDJI];
        [self ensureLowLatencyKeepAlive:deviceID];
        BOOL isDefault = [self isDefaultInput:deviceID];
        if (_keepAliveRunning) {
            self.statusMenuItem.title = isDefault ? @"已连接 · 低延迟 · 默认输入" : @"已连接 · 低延迟模式";
        } else if (self.lowLatencyError) {
            self.statusMenuItem.title = [NSString stringWithFormat:@"已连接 · %@", self.lowLatencyError];
        } else {
            self.statusMenuItem.title = @"已连接 · 正在启动低延迟模式…";
        }
        self.statusItem.button.image = [self statusImageConnected:YES];
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"%@ 已连接", self.mic.name];
    } else {
        self.statusMenuItem.title = self.lastError ?: (self.mic ? @"正在建立音频链路…" : @"等待配对 DJI Mic 2");
        [self stopLowLatencyKeepAlive];
        self.statusItem.button.image = [self statusImageConnected:NO];
        self.statusItem.button.toolTip = @"DJI Mic 2 未连接";
    }
}

- (void)handsFree:(IOBluetoothHandsFree *)device connected:(NSNumber *)status {
    if (status.intValue == kIOReturnSuccess) {
        [device connectSCO];
    } else {
        self.lastError = [NSString stringWithFormat:@"HFP 连接失败：0x%x", status.intValue];
    }
    [self refreshStatus:nil];
}

- (void)handsFree:(IOBluetoothHandsFree *)device scoConnectionOpened:(NSNumber *)status {
    if (status.intValue != kIOReturnSuccess) self.lastError = [NSString stringWithFormat:@"SCO 音频失败：0x%x", status.intValue];
    [self refreshStatus:nil];
}

- (void)handsFree:(IOBluetoothHandsFree *)device disconnected:(NSNumber *)status {
    [self refreshStatus:nil];
}

- (void)handsFree:(IOBluetoothHandsFree *)device scoConnectionClosed:(NSNumber *)status {
    [self refreshStatus:nil];
}

- (void)openSoundSettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Sound-Settings.extension"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)showMessage:(NSString *)message {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"DJI Mic 2 Bridge";
    alert.informativeText = message;
    [alert runModal];
}

- (void)quit:(id)sender {
    [self stopLowLatencyKeepAlive];
    [self.gateway disconnect];
    [NSApp terminate:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self removeOutputDeviceListeners];
    [self stopLowLatencyKeepAlive];
    [self.gateway disconnect];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

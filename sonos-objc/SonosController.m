//
//  SonosController.m
//  Sonos Controller
//
//  Created by Axel Möller on 16/11/13.
//  Copyright (c) 2013 Appreviation AB. All rights reserved.
//

#import "SonosController.h"
#import <AFNetworking/AFNetworking.h>
#import "XMLReader.h"

#if !defined MAX
#define MAX(a,b) \
({ __typeof__ (a) __a = (a); \
__typeof__ (b) __b = (b); \
__a > __b ? __a : __b; })
#endif

#if !defined MIN
#define MIN(a,b) \
({ __typeof__ (a) __a = (a); \
__typeof__ (b) __b = (b); \
__a < __b ? __a : __b; })
#endif

@interface SonosController()

@property (nonatomic, strong) AFHTTPSessionManager *httpSessionManager;
@property (nonatomic, assign, readwrite) NSInteger cachedVolume;
@property (nonatomic, strong) NSDate *cachedVolumeDate;
@property (nonatomic, assign) NSInteger pendingVolume;
@property (nonatomic, assign) BOOL volumeSetRequestPending;

- (void)upnp:(NSString *)url soap_service:(NSString *)soap_service soap_action:(NSString *)soap_action soap_arguments:(NSString *)soap_arguments completion:(void (^)(NSDictionary *, NSError *))block;
@end

@implementation SonosController

- (id)initWithIP:(NSString *)ip_ {
    self = [self initWithIP:ip_ port:1400];
    return self;
}

- (id)initWithIP:(NSString *)ip_ port:(int)port_ {
    if (self = [super init]) {
        _ip = ip_;
        _port = port_;
        _slaves = [[NSMutableArray alloc] init];
        _httpSessionManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        _httpSessionManager.responseSerializer = [[AFHTTPResponseSerializer alloc] init];
    }
    
    return self;
}

- (void)upnp:(NSString *)url soap_service:(NSString *)soap_service soap_action:(NSString *)soap_action soap_arguments:(NSString *)soap_arguments completion:(void (^)(NSDictionary *, NSError *))block {
    
    // Create Body data
    NSMutableString *post_xml = [[NSMutableString alloc] init];
    [post_xml appendString:@"<s:Envelope xmlns:s='http://schemas.xmlsoap.org/soap/envelope/' s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/'>"];
    [post_xml appendString:@"<s:Body>"];
    [post_xml appendFormat:@"<u:%@ xmlns:u='%@'>", soap_action, soap_service];
    [post_xml appendString:soap_arguments];
    [post_xml appendFormat:@"</u:%@>", soap_action];
    [post_xml appendString:@"</s:Body>"];
    [post_xml appendString:@"</s:Envelope>"];
    
    // Create HTTP Request
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%d%@", self.ip, self.port, url]]];
    [request setHTTPMethod:@"POST"];
    [request setTimeoutInterval:15.0];
    
    // Set headers
    [request addValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
    [request addValue:[NSString stringWithFormat:@"%@#%@", soap_service, soap_action] forHTTPHeaderField:@"SOAPACTION"];
    
    // Set Body
    [request setHTTPBody:[post_xml dataUsingEncoding:NSUTF8StringEncoding]];

    NSURLSessionDataTask *dataTask = [self.httpSessionManager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        if (block) {
            NSDictionary *responseDictionary = (!error) ? [XMLReader dictionaryForXMLData:responseObject error:nil] : nil;
            block(responseDictionary, error);
        }
    }];
    [dataTask resume];
}

- (void)play:(NSString *)track completion:(void (^)(NSDictionary *response, NSError *error))block {
    if(track) {
        NSString *meta = @"<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\"><item id=\"10000000spotify%3atrack%3a3bT5PDBhVj4ifU11zQvGP2\" restricted=\"true\">\
            <dc:title></dc:title>\
            <upnp:class>object.item.audioItem.musicTrack</upnp:class>\
            <desc id=\"cdudn\" nameSpace=\"urn:schemas-rinconnetworks-com:metadata-1-0/\">SA_RINCON2311_X_#Svc2311-0-Token</desc>\
            </item>\
            </DIDL-Lite>";
        
        [self
            upnp:@"/MediaRenderer/AVTransport/Control"
            soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
            soap_action:@"SetAVTransportURI"
            soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><CurrentURI>%@</CurrentURI><CurrentURIMetaData>%@</CurrentURIMetaData>", track, meta]
            completion:^(id responseObject, NSError *error) {
                [self play:nil completion:block];
            }];
    } else {
        [self
            upnp:@"/MediaRenderer/AVTransport/Control"
            soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
            soap_action:@"Play"
            soap_arguments:@"<InstanceID>0</InstanceID><Speed>1</Speed>"
            completion:block];
    }
}

- (void)play:(NSString *)track URIMetaData:(NSString *)URIMetaData completion:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"SetAVTransportURI"
        soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><CurrentURI>%@</CurrentURI><CurrentURIMetaData>%@</CurrentURIMetaData>", track, URIMetaData]
        completion:^(id responseObject, NSError *error) {
            if (error) {
                if (block) {
                    block(responseObject, error);
                }
                return;
            }
            [self play:nil completion:block];
        }];
}

- (void)playSpotifyTrack:(NSString *)track completion:(void (^)(NSDictionary *reponse, NSError *error))block {
    NSString *trackEncoded = [track stringByReplacingOccurrencesOfString:@":" withString:@"%%3a"];
    NSString *trackURI = [NSString stringWithFormat:@"x-sonos-spotify:%@?sid=9&amp;flags=32", trackEncoded];
    NSString *metaData = [NSString stringWithFormat:
                          @"<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:r\"urn:schemas-rinconnetworks-com:metadata-1-0\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\"> \
                          <item id=\"10030020%@\" parentID=\"\" restricted=\"true\"> \
                          <upnp:class>object.item.audioItem.musicTrack</upnp:class> \
                          <desc id=\"cdudn\" nameSpace=\"urn:schemas-rinconnetworks-com:metadata-1-0/\">SA_RINCON2311_X_#Svc2311-0-Token</desc> \
                          </item> \
                          </DIDL-Lite>", trackEncoded];
    metaData = [[[metaData stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"] stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    [self play:trackURI URIMetaData:metaData completion:block];
}

- (void)playQueuePosition:(int)position completion:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"Seek"
        soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><Unit>TRACK_NR</Unit><Target>%d</Target>", position]
        completion:^(NSDictionary *response, NSError *error){
            if(error) {
                if(block) {
                    block(response, error);
                }
                return;
            }
            [self play:nil completion:block];
     }];
}

- (void)pause:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"Pause"
        soap_arguments:@"<InstanceID>0</InstanceID><Speed>1</Speed>"
        completion:block];
}

- (void)togglePlayback:(void (^)(BOOL, NSDictionary *reponse, NSError *error))block {
    [self playbackStatus:^(BOOL playing, NSDictionary *response, NSError *error){
        if(playing) {
            [self pause:^(NSDictionary *response, NSError *error){
                if(block) {
                    block(NO, response, error);
                }
            }];
        }
        else {
            [self play:nil completion:^(NSDictionary *response, NSError *error){
                if(block) {
                    block(!error, response, error);
                }
            }];
        }
    }];
}

- (void)next:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"Next"
        soap_arguments:@"<InstanceID>0</InstanceID><Speed>1</Speed>"
        completion:block];
}

- (void)previous:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"Previous"
        soap_arguments:@"<InstanceID>0</InstanceID><Speed>1</Speed>"
        completion:block];
}

- (void)clearQueue:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"RemoveAllTracksFromQueue"
        soap_arguments:@"<InstanceID>0</InstanceID>"
        completion:block];
}

- (void)queue:(NSString *)track replace:(BOOL)replace completion:(void (^)(NSDictionary *reponse, NSError *error))block {
    if(replace) {
        [self clearQueue:^(NSDictionary *response, NSError *error){
            if(error) {
                if(block) {
                    block(response, error);
                }
                return;
            }
            [self queue:track replace:NO completion:block];
        }];
    } else {
        [self
         upnp:@"/MediaRenderer/AVTransport/Control"
         soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
         soap_action:@"AddURIToQueue"
         soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><EnqueuedURI>%@</EnqueuedURI><EnqueuedURIMetaData></EnqueuedURIMetaData><DesiredFirstTrackNumberEnqueued>1</DesiredFirstTrackNumberEnqueued><EnqueueAsNext>0</EnqueueAsNext>", track]
         completion:block];
    }
}

- (void)queue:(NSString *)track URIMetaData:(NSString *)URIMetaData replace:(BOOL)replace completion:(void (^)(NSDictionary *reponse, NSError *error))block {
    if(replace) {
        [self clearQueue:^(NSDictionary *response, NSError *error){
            if(error) {
                if(block) {
                    block(response, error);
                }
                return;
            }
            [self queue:track URIMetaData:URIMetaData replace:NO completion:block];
        }];
    } else {
        [self
         upnp:@"/MediaRenderer/AVTransport/Control"
         soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
         soap_action:@"AddURIToQueue"
         soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><EnqueuedURI>%@</EnqueuedURI><EnqueuedURIMetaData>%@</EnqueuedURIMetaData><DesiredFirstTrackNumberEnqueued>1</DesiredFirstTrackNumberEnqueued><EnqueueAsNext>0</EnqueueAsNext>", track, URIMetaData]
         completion:block];
    }
}

- (void)queueSpotifyPlaylist:(NSString *)playlist replace:(BOOL)replace completion:(void (^)(NSDictionary *reponse, NSError *error))block {
    
    NSArray *playlistURI = [playlist componentsSeparatedByString:@":"];
    NSString *playlistOwner = [playlistURI objectAtIndex:2];
    NSString *playlistID = [playlistURI objectAtIndex:4];
    
    NSString *meta = [NSString stringWithFormat:
                      @"<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\"> \
                      <item id=\"10060a6cspotify%%3auser%%3a%@%%3aplaylist%%3a%@\" parentID=\"100a0664playlists\" restricted=\"true\"> \
                      <upnp:class>object.container.playlistContainer</upnp:class> \
                      <desc id=\"cdudn\" nameSpace=\"urn:schemas-rinconnetworks-com:metadata-1-0/\">SA_RINCON2311_X_#Svc2311-0-Token</desc> \
                      </item> \
                      </DIDL-Lite>", playlistOwner, playlistID];
    
    meta = [[[meta stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"] stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    
    if(replace) {
        [self clearQueue:^(NSDictionary *response, NSError *error){
            if(error) {
                NSLog(@"Error clearing queue: %@", error.localizedDescription);
                if(block) {
                    block(response, error);
                    return;
                }
            }
                
            [self
                upnp:@"/MediaRenderer/AVTransport/Control"
                soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
                soap_action:@"AddURIToQueue"
                soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><EnqueuedURI>x-rincon-cpcontainer:10060a6cspotify%%3auser%%3a%@%%3aplaylist%%3a%@</EnqueuedURI><EnqueuedURIMetaData>%@</EnqueuedURIMetaData><DesiredFirstTrackNumberEnqueued>0</DesiredFirstTrackNumberEnqueued><EnqueueAsNext>0</EnqueueAsNext>", playlistOwner, playlistID, meta]
                completion:block];
        }];
    } else {
        [self
            upnp:@"/MediaRenderer/AVTransport/Control"
            soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
            soap_action:@"AddURIToQueue"
            soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><EnqueuedURI>x-rincon-cpcontainer:10060a6cspotify%%3auser%%3a%@%%3aplaylist%%3a%@</EnqueuedURI><EnqueuedURIMetaData>%@</EnqueuedURIMetaData><DesiredFirstTrackNumberEnqueued>0</DesiredFirstTrackNumberEnqueued><EnqueueAsNext>0</EnqueueAsNext>", playlistOwner, playlistID, meta]
            completion:block];
    }
}

- (void)getVolume:(NSTimeInterval)maxCacheAge completion:(void (^)(NSInteger volume, NSDictionary *response, NSError *))block {
    if (self.volumeSetRequestPending) {
        if(block) {
            block(self.pendingVolume, nil, nil);
        }
        return;
    }

    if (maxCacheAge > 0 && self.cachedVolumeDate && -[self.cachedVolumeDate timeIntervalSinceNow] <= maxCacheAge) {
        if(block) {
            block(self.cachedVolume, nil, nil);
        }
        return;
    }
    
    [self
        upnp:@"/MediaRenderer/RenderingControl/Control"
        soap_service:@"urn:schemas-upnp-org:service:RenderingControl:1"
        soap_action:@"GetVolume"
        soap_arguments:@"<InstanceID>0</InstanceID><Channel>Master</Channel>"
        completion:^(NSDictionary *response, NSError *error) {
            NSString *value = response[@"s:Envelope"][@"s:Body"][@"u:GetVolumeResponse"][@"CurrentVolume"][@"text"];
            if(error || ([value length] == 0)) {
                block(0, response, error);
            }
            else {
                NSInteger volume = [value integerValue];
                self.cachedVolume = volume;
                self.cachedVolumeDate = [NSDate date];
                block(volume, response, nil);
            }
        }];
}

- (void)getVolume:(void (^)(NSInteger volume, NSDictionary *response, NSError *))block {
    return [self getVolume:0.0 completion:block];
}

- (void)setVolume:(NSInteger)volume mergeRequests:(BOOL)mergeRequests completion:(void (^)(NSDictionary *response, NSError *error))block {
    volume = MIN(MAX(volume, 0), 100);

    self.pendingVolume = volume;
    if (mergeRequests && self.volumeSetRequestPending) {
        if (block) {
            block(nil, nil);
        }
        return;
    }

    [self
        upnp:@"/MediaRenderer/RenderingControl/Control"
        soap_service:@"urn:schemas-upnp-org:service:RenderingControl:1"
        soap_action:@"SetVolume"
        soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>%ld</DesiredVolume>", (long)volume]
        completion:^(NSDictionary *response, NSError *error) {
            self.volumeSetRequestPending = false;
            if (!error) {
                self.cachedVolume = volume;
                self.cachedVolumeDate = [NSDate date];
            }
            if (mergeRequests && self.pendingVolume != volume) {
                [self setVolume:self.pendingVolume mergeRequests:YES completion:nil];
            }
            if (block) {
                block(response, error);
            }
        }];
    self.volumeSetRequestPending = mergeRequests;
}

- (void)setVolume:(NSInteger)volume completion:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self setVolume:volume mergeRequests:NO completion:block];
}

- (void)getMute:(void (^)(BOOL mute, NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/RenderingControl/Control"
        soap_service:@"urn:schemas-upnp-org:service:RenderingControl:1"
        soap_action:@"GetMute"
        soap_arguments:@"<InstanceID>0</InstanceID><Channel>Master</Channel>"
        completion:^(NSDictionary *response, NSError *error) {
            if(!block) {
                return;
            }
            if(error) {
                block(NO, response, error);
                return;
            }

            NSString *stateStr = response[@"s:Envelope"][@"s:Body"][@"u:GetMuteResponse"][@"CurrentMute"][@"text"];
            BOOL state = [stateStr isEqualToString:@"1"] ? TRUE : FALSE;
            block(state, response, nil);
    }];
}

- (void)setMute:(BOOL)mute completion:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/RenderingControl/Control"
        soap_service:@"urn:schemas-upnp-org:service:RenderingControl:1"
        soap_action:@"SetMute"
        soap_arguments:[NSString stringWithFormat:@"<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredMute>%d</DesiredMute>", mute]
        completion:block];
}

- (void)trackInfo:(void (^)(NSString *artist, NSString *title, NSString *album, NSURL *albumArt, NSInteger time, NSInteger duration, NSInteger queueIndex, NSString *trackURI, NSString *protocol, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"GetPositionInfo"
        soap_arguments:@"<InstanceID>0</InstanceID>"
        completion:^(NSDictionary *response, NSError *error) {
            if(!block) {
                return;
            }
            if(error) {
                block(nil, nil, nil, nil, 0, 0, 0, nil, nil, error);
                return;
            }
         
            NSDictionary *positionInfoResponse = response[@"s:Envelope"][@"s:Body"][@"u:GetPositionInfoResponse"];
            NSDictionary *trackMetaData = [XMLReader dictionaryForXMLString:positionInfoResponse[@"TrackMetaData"][@"text"] error:nil];
         
            // Save track meta data
            NSString *artist = trackMetaData[@"DIDL-Lite"][@"item"][@"dc:creator"][@"text"];
            NSString *title = trackMetaData[@"DIDL-Lite"][@"item"][@"dc:title"][@"text"];
            NSString *album = trackMetaData[@"DIDL-Lite"][@"item"][@"upnp:album"][@"text"];
            NSURL *albumArt = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%d%@", self.ip, self.port, trackMetaData[@"DIDL-Lite"][@"item"][@"upnp:albumArtURI"][@"text"]]];
         
            // Convert current progress time to seconds
            NSString *timeString = positionInfoResponse[@"RelTime"][@"text"];
            NSArray *times = [timeString componentsSeparatedByString:@":"];
            int hours = [[times objectAtIndex:0] intValue] * 3600;
            int minutes = [[times objectAtIndex:1] intValue] * 60;
            int seconds = [[times objectAtIndex:2] intValue];
            NSInteger time = hours + minutes + seconds;
         
            // Convert track duration time to seconds
            NSString *durationString = positionInfoResponse[@"TrackDuration"][@"text"];
            NSArray *durations = [durationString componentsSeparatedByString:@":"];
            int durationHours = [[durations objectAtIndex:0] intValue] * 3600;
            int durationMinutes = [[durations objectAtIndex:1] intValue] * 60;
            int durationSeconds = [[durations objectAtIndex:2] intValue];
            NSInteger duration = durationHours + durationMinutes + durationSeconds;
         
            NSInteger queueIndex = [positionInfoResponse[@"Track"][@"text"] integerValue];
         
            NSString *trackURI = positionInfoResponse[@"TrackURI"][@"text"];
            NSString *protocol = trackMetaData[@"DIDL-Lite"][@"item"][@"res"][@"protocolInfo"];
         
            block(artist, title, album, albumArt, time, duration, queueIndex, trackURI, protocol, error);
     }];
}

- (void)mediaInfo:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"GetMediaInfo"
        soap_arguments:@"<InstanceID>0</InstanceID>"
        completion:block];
}

- (void)playbackStatus:(void (^)(BOOL playing, NSDictionary*, NSError *error))block {
    [self status:^(NSDictionary *response, NSError *error){
        if(!block) {
            return;
        }
        if(error) {
            block(NO, nil, error);
            return;
        }
        NSString *playState = response[@"CurrentTransportState"];
        if([playState isEqualToString:@"PLAYING"]) {
            block(YES, response, nil);
        }
        else if([playState isEqualToString:@"PAUSED_PLAYBACK"] || [playState isEqualToString:@"STOPPED"]) {
            block(NO, response, nil);
        }
        else {
            block(NO, response, nil);
        }
    }];
}

- (void)status:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaRenderer/AVTransport/Control"
        soap_service:@"urn:schemas-upnp-org:service:AVTransport:1"
        soap_action:@"GetTransportInfo"
        soap_arguments:@"<InstanceID>0</InstanceID>"
        completion:^(NSDictionary *response, NSError *error) {
            if(!block) {
                return;
            }
            if(error) {
                block(nil, error);
                return;
            }

            NSString *transportState = response[@"s:Envelope"][@"s:Body"][@"u:GetTransportInfoResponse"][@"CurrentTransportState"][@"text"];
            NSDictionary *returnData = transportState ? @{@"CurrentTransportState" : transportState} : @{};
            block(returnData, nil);
    }];
}

- (void)browse:(void (^)(NSDictionary *reponse, NSError *error))block {
    [self
        upnp:@"/MediaServer/ContentDirectory/Control"
        soap_service:@"urn:schemas-upnp-org:service:ContentDirectory:1"
        soap_action:@"Browse"
        soap_arguments:@"<ObjectID>Q:0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>0</RequestedCount><SortCriteria></SortCriteria>"
        completion:^(NSDictionary *response, NSError *error) {
            if (!block) {
                return;
            }
            if (error) {
                block(nil, error);
                return;
            }

            NSDictionary *queue = [XMLReader dictionaryForXMLString:response[@"s:Envelope"][@"s:Body"][@"u:BrowseResponse"][@"Result"][@"text"] error:nil];
            NSMutableArray *queue_items = [NSMutableArray array];
            for(NSDictionary *queue_item in queue[@"DIDL-Lite"][@"item"]  ) {
                // Spotify
                if([queue_item[@"res"][@"protocolInfo"] isEqualToString:@"sonos.com-spotify:*:audio/x-spotify:*"]) {
                    NSDictionary *item = @{@"MetaDataCreator" : queue_item[@"dc:creator"][@"text"],
                                           @"MetaDataTitle" : queue_item[@"dc:title"][@"text"],
                                           @"MetaDataAlbum" : queue_item[@"upnp:album"][@"text"],
                                           @"MetaDataAlbumArtURI": queue_item[@"upnp:albumArtURI"][@"text"],
                                           @"MetaDataTrackURI": queue_item[@"res"][@"text"]};
                    [queue_items addObject:item];
                }
                 
                // HTTP Streaming (SoundCloud?)
                if([queue_item[@"res"][@"protocolInfo"] isEqualToString:@"sonos.com-http:*:audio/mpeg:*"]) {
                    NSDictionary *item = @{@"MetaDataCreator" : queue_item[@"dc:creator"][@"text"],
                                           @"MetaDataTitle" : queue_item[@"dc:title"][@"text"],
                                           @"MetaDataAlbum" : @"",
                                           @"MetaDataAlbumArtURI" : queue_item[@"upnp:albumArtURI"][@"text"],
                                           @"MetaDataTrackURI" : queue_item[@"res"][@"text"]};
                    [queue_items addObject:item];
                }
            }

            NSMutableDictionary *returnData = [[NSMutableDictionary alloc] init];
            NSString *totalMatches = response[@"s:Envelope"][@"s:Body"][@"u:BrowseResponse"][@"TotalMatches"][@"text"];
            if (totalMatches) {
                returnData[@"TotalMatches"] = totalMatches;
            }
            returnData[@"QueueItems"] = queue_items;
            block(returnData, nil);
    }];
}

-(BOOL)isEqual:(SonosController *)other {
    return [self.ip isEqual:other.ip] && (self.port == other.port);
}

- (NSUInteger)hash {
    return [self.ip hash] ^ self.port;
}

@end

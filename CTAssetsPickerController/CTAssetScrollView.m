/*
 
 MIT License (MIT)
 
 Copyright (c) 2015 Clement CN Tsang
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */

#import <PureLayout/PureLayout.h>
#import "CTAssetScrollView.h"
#import "CTAssetPlayButton.h"
#import "PHAsset+CTAssetsPickerController.h"
#import "NSBundle+CTAssetsPickerController.h"
#import "UIImage+CTAssetsPickerController.h"




NSString * const CTAssetScrollViewDidTapNotification = @"CTAssetScrollViewDidTapNotification";
NSString * const CTAssetScrollViewPlayerWillPlayNotification = @"CTAssetScrollViewPlayerWillPlayNotification";
NSString * const CTAssetScrollViewPlayerWillPauseNotification = @"CTAssetScrollViewPlayerWillPauseNotification";
NSString * const CTAssetScrollViewShouldDismissNotification = @"CTAssetScrollViewShouldDismissNotification";




@interface CTAssetScrollView ()
<UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) AVPlayer *player;

@property (nonatomic, assign) BOOL didLoadPlayerItem;

@property (nonatomic, assign) CGFloat perspectiveZoomScale;

@property (nonatomic, strong) UIImageView *imageView;

@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIActivityIndicatorView *activityView;
@property (nonatomic, strong) CTAssetPlayButton *playButton;
@property (nonatomic, strong) CTAssetSelectionButton *selectionButton;

@property (nonatomic, strong) NSLayoutConstraint *imageWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;

@property (nonatomic, assign) BOOL shouldUpdateConstraints;
@property (nonatomic, assign) BOOL didSetupConstraints;


@end

@implementation CTAssetScrollView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self)
    {
        _shouldUpdateConstraints            = YES;
        self.allowsSelection                = NO;
        self.showsVerticalScrollIndicator   = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.bouncesZoom                    = YES;
        self.decelerationRate               = UIScrollViewDecelerationRateFast;
        self.delegate                       = self;
        
        [self setupViews];
        [self addGestureRecognizers];
    }
    
    return self;
}

- (void)dealloc
{
    [self removePlayerNotificationObserver];
    [self removePlayerLoadedTimeRangesObserver];
    [self removePlayerRateObserver];
}


#pragma mark - Setup

- (void)setupViews
{
    UIImageView *imageView = [UIImageView new];
    imageView.isAccessibilityElement    = YES;
    imageView.accessibilityTraits       = UIAccessibilityTraitImage;
    imageView.layer.masksToBounds       = YES;
    self.imageView = imageView;
    [self addSubview:self.imageView];
    
    UIProgressView *progressView =
    [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView = progressView;
    [self addSubview:self.progressView];
    
    UIActivityIndicatorView *activityView =
    [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.activityView = activityView;
    [self addSubview:self.activityView];
    
    CTAssetPlayButton *playButton = [CTAssetPlayButton newAutoLayoutView];
    self.playButton = playButton;
    [self addSubview:self.playButton];
    
    CTAssetSelectionButton *selectionButton = [CTAssetSelectionButton newAutoLayoutView];
    self.selectionButton = selectionButton;
    [self addSubview:self.selectionButton];
}


#pragma mark - Update auto layout constraints

- (void)updateConstraints
{
    if (!self.didSetupConstraints)
    {
        [self updateSelectionButtonIfNeeded];
        [self autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero];
        [self updateProgressConstraints];
        [self updateActivityConstraints];
        
        self.didSetupConstraints = YES;
    }

    self.contentOffset = CGPointZero;
    [self updateContentFrameOffsetedBy:0];
    [super updateConstraints];
}

- (void)updateSelectionButtonIfNeeded
{
    if (!self.allowsSelection)
    {
        [self.selectionButton removeFromSuperview];
        self.selectionButton = nil;
    }
}

- (void)updateProgressConstraints
{
    [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultLow forConstraints:^{
        [self.progressView autoConstrainAttribute:ALAttributeLeading toAttribute:ALAttributeLeading ofView:self.superview withMultiplier:1 relation:NSLayoutRelationEqual];
        [self.progressView autoConstrainAttribute:ALAttributeTrailing toAttribute:ALAttributeTrailing ofView:self.superview withMultiplier:1 relation:NSLayoutRelationEqual];
        [self.progressView autoConstrainAttribute:ALAttributeBottom toAttribute:ALAttributeBottom ofView:self.superview withMultiplier:1 relation:NSLayoutRelationEqual];
    }];
    
    [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultHigh forConstraints:^{
        [self.progressView autoConstrainAttribute:ALAttributeLeading toAttribute:ALAttributeLeading ofView:self.imageView withMultiplier:1 relation:NSLayoutRelationGreaterThanOrEqual];
        [self.progressView autoConstrainAttribute:ALAttributeTrailing toAttribute:ALAttributeTrailing ofView:self.imageView withMultiplier:1 relation:NSLayoutRelationLessThanOrEqual];
        [self.progressView autoConstrainAttribute:ALAttributeBottom toAttribute:ALAttributeBottom ofView:self.imageView withMultiplier:1 relation:NSLayoutRelationLessThanOrEqual];
    }];
}

- (void)updateActivityConstraints
{
    [self.activityView autoAlignAxis:ALAxisVertical toSameAxisOfView:self.superview];
    [self.activityView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.superview];
}

- (void)updateContentFrameOffsetedBy:(CGFloat)yOffset
{
    CGRect imageFrame = [self calculateContentFrameOffsetedBy:yOffset];
    self.imageView.frame = imageFrame;
    if (CGRectIsEmpty(imageFrame))
        return;
    self.selectionButton.frame = CGRectMake((int)(imageFrame.origin.x + imageFrame.size.width - 31),
                                            (int)(imageFrame.origin.y + imageFrame.size.height - 31),
                                            31, 31);
    if (!self.playButton.isHidden) {
        self.playButton.frame = CGRectMake(imageFrame.origin.x + imageFrame.size.width / 2 - 35,
                                           imageFrame.origin.y + imageFrame.size.height / 2 - 35,
                                           70, 70);
    }
}

- (CGRect)calculateContentFrameOffsetedBy:(CGFloat)yOffset {
    if (!self.asset)
        return CGRectZero;
    CGFloat inset = 10;
    CGSize boundsSize = self.bounds.size;

    CGFloat w = self.zoomScale * self.asset.pixelWidth - inset * 2;
    CGFloat h = self.zoomScale * self.asset.pixelHeight
        - inset * 2 * self.asset.pixelHeight / (self.asset.pixelWidth ?: 1);

    CGFloat dx = (boundsSize.width - w) / 2.0;
    CGFloat dy = (boundsSize.height - h) / 2.0;

    return CGRectMake(dx, dy + yOffset, w, h);
}

#pragma mark - Start/stop loading animation

- (void)startActivityAnimating
{
    [self.playButton setHidden:YES];
    [self.selectionButton setHidden:YES];
    [self.activityView startAnimating];
    [self postPlayerWillPlayNotification];
}

- (void)stopActivityAnimating
{
    [self.playButton setHidden:NO];
    [self.selectionButton setHidden:NO];
    [self.activityView stopAnimating];
    [self postPlayerWillPauseNotification];
}


#pragma mark - Set progress

- (void)setProgress:(CGFloat)progress
{
#if !defined(CT_APP_EXTENSIONS)
    [UIApplication sharedApplication].networkActivityIndicatorVisible = progress < 1;
#endif
    [self.progressView setProgress:progress animated:(progress < 1)];
    self.progressView.hidden = progress == 1;
}

// To mimic image downloading progress
// as PHImageRequestOptions does not work as expected
- (void)mimicProgress
{
    CGFloat progress = self.progressView.progress;

    if (progress < 0.95)
    {
        int lowerbound = progress * 100 + 1;
        int upperbound = 95;
        
        int random = lowerbound + arc4random() % (upperbound - lowerbound);
        CGFloat randomProgress = random / 100.0f;

        [self setProgress:randomProgress];
        
        NSInteger randomDelay = 1 + arc4random() % (3 - 1);
        [self performSelector:@selector(mimicProgress) withObject:nil afterDelay:randomDelay];
    }
}


#pragma mark - asset size

- (CGSize)assetSize
{
    return CGSizeMake(self.asset.pixelWidth, self.asset.pixelHeight);
}


#pragma mark - Bind asset image

- (void)bind:(PHAsset *)asset image:(UIImage *)image requestInfo:(NSDictionary *)info
{
    self.asset = asset;
    self.imageView.accessibilityLabel = asset.accessibilityLabel;    
    self.playButton.hidden = [asset ctassetsPickerIsPhoto];
    
    BOOL isDegraded = [info[PHImageResultIsDegradedKey] boolValue];
    
    if (self.image == nil || !isDegraded)
    {
        BOOL zoom = (!self.image);
        self.image = image;
        self.imageView.image = image;
        if (self.imageView.layer.transform.m11) {
            self.imageView.layer.cornerRadius = 20 / self.imageView.layer.transform.m11;
        }
        
        if (isDegraded)
            [self mimicProgress];
        else
            [self setProgress:1];

        [self setNeedsUpdateConstraints];
        [self updateConstraintsIfNeeded];        
        [self updateZoomScalesAndZoom:zoom];
    }
}


#pragma mark - Bind player item

- (void)bind:(AVPlayerItem *)playerItem requestInfo:(NSDictionary *)info
{
    [self unbindPlayerItem];
    
    AVPlayer *player = [AVPlayer playerWithPlayerItem:playerItem];
    AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
    playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    playerLayer.cornerRadius = 8;
    playerLayer.masksToBounds = YES;

    CALayer *layer = self.imageView.layer;
    [layer addSublayer:playerLayer];
    playerLayer.frame = layer.bounds;
    
    self.player = player;

    [self addPlayerNotificationObserver];
    [self addPlayerLoadedTimeRangesObserver];
}

- (void)unbindPlayerItem
{
    [self removePlayerNotificationObserver];
    [self removePlayerLoadedTimeRangesObserver];

    for (CALayer *layer in self.imageView.layer.sublayers)
        [layer removeFromSuperlayer];
    
    self.player = nil;
}



#pragma mark - Upate zoom scales

- (void)updateZoomScalesAndZoom:(BOOL)zoom
{
    if (!self.asset)
        return;
    
    CGSize assetSize    = [self assetSize];
    CGSize boundsSize   = self.bounds.size;
    
    CGFloat xScale = boundsSize.width / assetSize.width;    //scale needed to perfectly fit the image width-wise
    CGFloat yScale = boundsSize.height / assetSize.height;  //scale needed to perfectly fit the image height-wise
    
    CGFloat minScale = MIN(xScale, yScale);
    CGFloat maxScale = 3.0 * minScale;
    
    if ([self.asset ctassetsPickerIsVideo])
    {
        self.minimumZoomScale = minScale;
        self.maximumZoomScale = minScale;
    }
    
    else
    {
        self.minimumZoomScale = minScale;
        self.maximumZoomScale = maxScale;
    }
    
    // update perspective zoom scale
    self.perspectiveZoomScale = (boundsSize.width > boundsSize.height) ? xScale : yScale;
    
    if (zoom)
        [self zoomToInitialScale];
}



#pragma mark - Zoom

- (void)zoomToInitialScale
{
    if ([self canPerspectiveZoom])
        [self zoomToPerspectiveZoomScaleAnimated:NO];
    else
        [self zoomToMinimumZoomScaleAnimated:NO];
}

- (void)zoomToMinimumZoomScaleAnimated:(BOOL)animated
{
    [self setZoomScale:self.minimumZoomScale animated:animated];
}

- (void)zoomToMaximumZoomScaleWithGestureRecognizer:(UITapGestureRecognizer *)recognizer
{
    CGRect zoomRect = [self zoomRectWithScale:self.maximumZoomScale withCenter:[recognizer locationInView:recognizer.view]];

    self.shouldUpdateConstraints = NO;
    
    [UIView animateWithDuration:0.3 animations:^{
        [self zoomToRect:zoomRect animated:NO];
        
        CGRect frame = self.imageView.frame;
        frame.origin.x = 0;
        frame.origin.y = 0;

        self.imageView.frame = frame;
    }];
}


#pragma mark - Perspective zoom

- (BOOL)canPerspectiveZoom
{
    CGSize assetSize    = [self assetSize];
    CGSize boundsSize   = self.bounds.size;
    
    CGFloat assetRatio  = assetSize.width / assetSize.height;
    CGFloat boundsRatio = boundsSize.width / boundsSize.height;
    
    // can perform perspective zoom when the difference of aspect ratios is smaller than 20%
    return (fabs( (assetRatio - boundsRatio) / boundsRatio ) < 0.2f);
}

- (void)zoomToPerspectiveZoomScaleAnimated:(BOOL)animated;
{
    CGRect zoomRect = [self zoomRectWithScale:self.perspectiveZoomScale];
    [self zoomToRect:zoomRect animated:animated];
}

- (CGRect)zoomRectWithScale:(CGFloat)scale
{
    CGSize targetSize;
    targetSize.width    = self.bounds.size.width / scale;
    targetSize.height   = self.bounds.size.height / scale;
    
    CGPoint targetOrigin;
    targetOrigin.x      = (self.asset.pixelWidth - targetSize.width) / 2.0;
    targetOrigin.y      = (self.asset.pixelHeight - targetSize.height) / 2.0;
    
    CGRect zoomRect;
    zoomRect.origin = targetOrigin;
    zoomRect.size   = targetSize;

    return zoomRect;
}


#pragma mark - Zoom with gesture recognizer

- (void)zoomWithGestureRecognizer:(UITapGestureRecognizer *)recognizer
{
    if (self.minimumZoomScale == self.maximumZoomScale)
        return;
    
    if ([self canPerspectiveZoom])
    {
        if ((self.zoomScale >= self.minimumZoomScale && self.zoomScale < self.perspectiveZoomScale) ||
            (self.zoomScale <= self.maximumZoomScale && self.zoomScale > self.perspectiveZoomScale))
            [self zoomToPerspectiveZoomScaleAnimated:YES];
        else
            [self zoomToMaximumZoomScaleWithGestureRecognizer:recognizer];
        
        return;
    }
    
    if (self.zoomScale < self.maximumZoomScale)
        [self zoomToMaximumZoomScaleWithGestureRecognizer:recognizer];
    else
        [self zoomToMinimumZoomScaleAnimated:YES];
}

- (CGRect)zoomRectWithScale:(CGFloat)scale withCenter:(CGPoint)center
{
    center = [self.imageView convertPoint:center fromView:self];
    
    CGRect zoomRect;
    
    zoomRect.size.height = self.imageView.frame.size.height / scale;
    zoomRect.size.width  = self.imageView.frame.size.width  / scale;
    
    zoomRect.origin.x    = center.x - ((zoomRect.size.width / 2.0));
    zoomRect.origin.y    = center.y - ((zoomRect.size.height / 2.0));
    
    return zoomRect;
}


#pragma mark - Gesture recognizers

- (void)addGestureRecognizers
{
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapping:)];
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapping:)];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    
    doubleTap.numberOfTapsRequired = 2.0;
    [singleTap requireGestureRecognizerToFail:doubleTap];

    
    singleTap.delegate = self;
    doubleTap.delegate = self;
    pan.delegate = self;
    
    [self addGestureRecognizer:singleTap];
    [self addGestureRecognizer:doubleTap];
    [self addGestureRecognizer:pan];
}


#pragma mark - Handle tappings

- (void)handleTapping:(UITapGestureRecognizer *)recognizer
{
    CGPoint offset = [recognizer locationInView:self.imageView];
    if (!CGRectContainsPoint(self.imageView.bounds, offset)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:CTAssetScrollViewDidTapNotification object:recognizer];
    }
    
    if (recognizer.numberOfTapsRequired == 2)
        [self zoomWithGestureRecognizer:recognizer];
}

#pragma mark - Pan

- (void)handlePan:(UIPanGestureRecognizer *)gr {
    CGPoint translation = [gr translationInView:self];

    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            CGFloat y = MAX(translation.y, 0);
            [self updateContentFrameOffsetedBy:y];
            break;
        }
        case UIGestureRecognizerStateEnded: {
            // If pan ended, decide it we should close or reset the view
            // based on the final position and the speed of the gesture
            CGPoint velocity = [gr velocityInView:self];
            BOOL shouldDismiss = (translation.y > self.frame.size.height * 0.2) || velocity.y > 1500;

            if (shouldDismiss) {
                [[NSNotificationCenter defaultCenter] postNotificationName:CTAssetScrollViewShouldDismissNotification object:nil];
            } else {
                [UIView animateWithDuration:0.2 animations:^{
                    [self updateContentFrameOffsetedBy:0];
                }];
            }
        }
        default: {
            [UIView animateWithDuration:0.2 animations:^{
                [self updateContentFrameOffsetedBy:0];
            }];
        }

    }
}

#pragma mark - Scroll view delegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.imageView;
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view
{
    self.shouldUpdateConstraints = YES;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    self.scrollEnabled = self.zoomScale != self.perspectiveZoomScale;
    
    if (self.shouldUpdateConstraints)
    {
        [self setNeedsUpdateConstraints];
        [self updateConstraintsIfNeeded];
    }
}


#pragma mark - Gesture recognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    return !([touch.view isDescendantOfView:self.playButton] || [touch.view isDescendantOfView:self.selectionButton]);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return [gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]];
}


#pragma mark - Notification observer

- (void)addPlayerNotificationObserver
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    [center addObserver:self
               selector:@selector(applicationWillResignActive:)
                   name:UIApplicationWillResignActiveNotification
                 object:nil];
}

- (void)removePlayerNotificationObserver
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
}



#pragma mark - Video player item key-value observer

- (void)addPlayerLoadedTimeRangesObserver
{
    [self.player addObserver:self
                  forKeyPath:@"currentItem.loadedTimeRanges"
                     options:NSKeyValueObservingOptionNew
                     context:nil];
}

- (void)removePlayerLoadedTimeRangesObserver
{
    @try {
        [self.player removeObserver:self forKeyPath:@"currentItem.loadedTimeRanges"];
    }
    @catch (NSException *exception) {
        // do nothing
    }
}

- (void)addPlayerRateObserver
{
    [self.player addObserver:self
                  forKeyPath:@"rate"
                     options:NSKeyValueObservingOptionNew
                     context:nil];
}

- (void)removePlayerRateObserver
{
    @try {
        [self.player removeObserver:self forKeyPath:@"rate"];
    }
    @catch (NSException *exception) {
        // do nothing
    }    
}


#pragma mark - Video playback Key-Value changed

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == self.player && [keyPath isEqual:@"currentItem.loadedTimeRanges"])
    {
        NSArray *timeRanges = change[NSKeyValueChangeNewKey];

        if (timeRanges && timeRanges.count)
        {
            CMTimeRange timeRange = [timeRanges.firstObject CMTimeRangeValue];
            
            if (CMTIME_COMPARE_INLINE(timeRange.duration, ==, self.player.currentItem.duration))
                [self performSelector:@selector(playerDidLoadItem:) withObject:object];
        }
    }
    
    if (object == self.player && [keyPath isEqual:@"rate"])
    {
        CGFloat rate = [[change valueForKey:NSKeyValueChangeNewKey] floatValue];
        
        if (rate > 0)
            [self performSelector:@selector(playerDidPlay:) withObject:object];
        
        if (rate == 0)
            [self performSelector:@selector(playerDidPause:) withObject:object];
    }
}



#pragma mark - Notifications

- (void)postPlayerWillPlayNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CTAssetScrollViewPlayerWillPlayNotification object:nil];
}

- (void)postPlayerWillPauseNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CTAssetScrollViewPlayerWillPauseNotification object:nil];
}


#pragma mark - Playback events

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self pauseVideo];
}


- (void)playerDidPlay:(id)sender
{
    [self setProgress:1];
    [self.playButton setHidden:YES];
    [self.selectionButton setHidden:YES];
    [self.activityView stopAnimating];
}


- (void)playerDidPause:(id)sender
{
    [self.playButton setHidden:NO];
    [self.selectionButton setHidden:NO];
}

- (void)playerDidLoadItem:(id)sender
{
    if (!self.didLoadPlayerItem)
    {
        [self setDidLoadPlayerItem:YES];
        [self addPlayerRateObserver];
        
        [self.activityView stopAnimating];
        [self playVideo];
    }
}


#pragma mark - Playback

- (void)playVideo
{
    if (self.didLoadPlayerItem)
    {
        if (CMTIME_COMPARE_INLINE(self.player.currentTime, == , self.player.currentItem.duration))
            [self.player seekToTime:kCMTimeZero];
        
        [self postPlayerWillPlayNotification];
        [self.player play];
    }
}

- (void)pauseVideo
{
    if (self.didLoadPlayerItem)
    {
        [self postPlayerWillPauseNotification];
        [self.player pause];
    }
    else
    {
        [self stopActivityAnimating];
        [self unbindPlayerItem];
    }
}


@end

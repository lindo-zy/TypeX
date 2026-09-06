#import "DXCell.h"

@implementation DXCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        
        self.contentView.backgroundColor = [UIColor clearColor];
        //self.backgroundColor = [UIColor clearColor];
        
        //_btn = [[UIButton alloc] initWithFrame:CGRectZero];
        _btn = [UIButton buttonWithType:UIButtonTypeSystem];
        
        //[_btn setTitle:_btn.title];
        _btn.translatesAutoresizingMaskIntoConstraints = NO;
        //[self.contentView addSubview:_btn];
        [self.contentView addSubview:_btn];
        
        [NSLayoutConstraint activateConstraints: @[
            [_btn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_btn.bottomAnchor constraintEqualToAnchor: self.contentView.bottomAnchor],
            [_btn.leadingAnchor constraintLessThanOrEqualToAnchor: self.contentView.leadingAnchor constant:-5],
            [_btn.trailingAnchor constraintLessThanOrEqualToAnchor: self.contentView.trailingAnchor constant:-5],
            [_btn.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor]
        ]];
    }
    return self;
}

@end

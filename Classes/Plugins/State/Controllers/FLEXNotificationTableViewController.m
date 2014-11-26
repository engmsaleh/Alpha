//
//  FLEXNotificationTableViewController.m
//  UICatalog
//
//  Created by Dal Rupnik on 11/11/14.
//  Copyright (c) 2014 f. All rights reserved.
//

#import "FLEXObjectExplorerFactory.h"
#import "FLEXObjectExplorerViewController.h"
#import "FLEXUtility.h"

#import "FLEXSystemNotification.h"

#import "FLEXNotificationCollector.h"
#import "FLEXNotificationTableViewController.h"

@interface FLEXNotificationTableViewController ()

@property (nonatomic, strong) NSArray *localNotifications;

@end

@implementation FLEXNotificationTableViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    style = UITableViewStyleGrouped;
    
    self = [super initWithStyle:style];
    
    if (self)
    {
        self.title = @"Notifications";
        self.localNotifications = [FLEXNotificationCollector sharedCollector].localNotifications;
    }
    
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0)
    {
        return 1;
    }
    else if (section == 1)
    {
        return self.localNotifications.count;
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (!cell)
    {
        UITableViewCellStyle style = (indexPath.section == 0) ? UITableViewCellStyleValue1 : UITableViewCellStyleSubtitle;
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:CellIdentifier];
        
        cell.detailTextLabel.minimumScaleFactor = 0.5;
        cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        cell.detailTextLabel.adjustsLetterSpacingToFitWidth = YES;
    }
    
    if (indexPath.section == 0)
    {
        [self updateCell:cell forRemoteNotificationAtIndexPath:indexPath];
    }
    else if (indexPath.section == 1)
    {
        [self updateCell:cell forLocalNotificationAtIndexPath:indexPath];
    }
    
    return cell;
}

- (void)updateCell:(UITableViewCell *)cell forRemoteNotificationAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.row)
    {
        case 0:
            cell.textLabel.text = @"Status";
            cell.detailTextLabel.text = [FLEXNotificationCollector sharedCollector].enabledNotificationTypes;
            
            break;
        /*case 1:
            cell.textLabel.text = @"System Processes";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", [UIDevice currentDevice].hs_processCount];
            
            break;*/
            
        default:
            break;
    }
}


- (void)updateCell:(UITableViewCell *)cell forLocalNotificationAtIndexPath:(NSIndexPath *)indexPath
{
    FLEXSystemNotification *notification = self.localNotifications[indexPath.row];
    
    cell.textLabel.text = notification.alertBody.length ? notification.alertBody : [notification.fireDate description];
    cell.detailTextLabel.text = notification.alertBody.length ? [notification.fireDate description] : @"";
}
#pragma mark - Table view delegate

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0)
    {
        return @"Remote";
    }
    else if (section == 1)
    {
        return @"Local";
    }
    
    return nil;
}

- (UIViewController *)viewControllerToPushForRowAtIndexPath:(NSIndexPath *)indexPath
{
    FLEXSystemNotification *systemNotification = self.localNotifications[indexPath.row];
    
    return [FLEXObjectExplorerFactory explorerViewControllerForObject:systemNotification];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 1)
    {
        UIViewController *viewControllerToPush = [self viewControllerToPushForRowAtIndexPath:indexPath];
        
        [self.navigationController pushViewController:viewControllerToPush animated:YES];
    }
}

@end

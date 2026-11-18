//
//  MLSettingsTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/26/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLSettingsTableViewController.h"
#import "MLWebViewController.h"
#import "MLSwitchCell.h"
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLXMPPManager.h>
#import "XMPPEdit.h"
#import "MonalAppDelegate.h"
#import "ActiveChatsViewController.h"
#import <Monal-Swift.h>

@import SafariServices;

enum kSettingSection {
    kSettingSectionAccounts,
    //VELO: tre schede come le Impostazioni della Velo Android (Aspetto / Privacy, Sicurezza, Notifiche / Dati...)
    kSettingSectionLook,
    kSettingSectionMain,
    kSettingSectionData,
    kSettingSectionSupport,
    kSettingSectionAbout,
    kSettingSectionCount
};

enum SettingsAccountRows {
    QuickSettingsRow,
    AdvancedSettingsRow,
    SettingsAccountRowsCnt
};

enum SettingsLookRows {
    VeloAppearanceRow,
    SettingsLookRowsCnt
};

enum SettingsMainRows {
    VeloPrivacyRow,
    VeloSecurityRow,
    VeloNotificationsRow,
    SoundsRow,
    SettingsMainRowsCnt
};

enum SettingsDataRows {
    VeloAttachmentsRow,
    VeloDiagnosticsRow,
    GeneralSettingsRow,
    SettingsDataRowsCnt
};

enum SettingsSupportRow {
    EmailRow,
    SubmitABugRow,
    OpenFAQRow,
    SettingsSupportRowCnt
};

enum SettingsAboutRows {
    RateMonalRow,
    OpenSourceRow,
    PrivacyRow,
    AboutRow,
#ifdef DEBUG
    LogRow,
#endif
    VersionRow,
    SettingsAboutRowsCntORLogRow,
    SettingsAboutRowsWithLogCnt
};

//this will hold all disabled rows of all enums (this is needed because the code below still references these rows)
enum DummySettingsRows {
    DummySettingsRowsBegin = 100,
};

@interface MLSettingsTableViewController () {
    int _tappedVersionInfo;
}

@property (nonatomic, strong) NSArray* sections;
@property (nonatomic, strong) NSArray* accountRows;
@property (nonatomic, strong) NSArray* appRows;
@property (nonatomic, strong) NSArray* supportRows;
@property (nonatomic, strong) NSDateFormatter* uptimeFormatter;

@property (nonatomic, strong) NSIndexPath* selected;

@end

@implementation MLSettingsTableViewController 


-(IBAction) close:(id) sender
{
    _tappedVersionInfo = 0;
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self setupAccountsView];

    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"AccountCell"];

    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
#if !TARGET_OS_MACCATALYST
    self.splitViewController.primaryBackgroundStyle = UISplitViewControllerBackgroundStyleSidebar;
#endif
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshAccountList];

    _tappedVersionInfo = 0;
    self.selected = nil;
    
    [self presentSplitPlaceholder];
}

-(void) viewWillDisappear:(BOOL) animated
{
    [super viewWillDisappear:animated];
    [((MonalAppDelegate*)UIApplication.sharedApplication.delegate).activeChats sheetDismissed];
}

-(void) presentSplitPlaceholder
{
    // only show placeholder if we use a split view
    if(!self.splitViewController.collapsed)
    {
        DDLogVerbose(@"Presenting Settings Placeholder...");
        UIViewController* detailsViewController = [[SwiftuiInterface new] makeViewWithName:@"ChatPlaceholder"];
        [self showDetailViewController:detailsViewController sender:self];
    }
}

#pragma mark - key commands

-(BOOL) canBecomeFirstResponder
{
    return YES;
}

-(NSArray<UIKeyCommand*>*) keyCommands
{
    return @[[UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(close:)]];
}

#pragma mark - Table view data source

-(NSInteger) numberOfSectionsInTableView:(UITableView*) tableView
{
    return kSettingSectionCount;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch(section)
    {
        case kSettingSectionAccounts: return [self getAccountNum] + SettingsAccountRowsCnt;
        case kSettingSectionLook: return SettingsLookRowsCnt;
        case kSettingSectionMain: return SettingsMainRowsCnt;
        case kSettingSectionData: return SettingsDataRowsCnt;
        case kSettingSectionSupport: return 0;      //VELO: supporto, segnalazioni e FAQ portavano ai siti di Monal fuori da Tor
#ifndef DEBUG
        case kSettingSectionAbout: return [[HelperTools defaultsDB] boolForKey:@"showLogInSettings"] ? SettingsAboutRowsWithLogCnt : SettingsAboutRowsCntORLogRow;
#else
        case kSettingSectionAbout: return SettingsAboutRowsCntORLogRow;
#endif
        default:
            unreachable();
    }
    return 0;
}

-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    if([segue.identifier isEqualToString:@"showOpenSource"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        NSBundle* mainBundle = [NSBundle mainBundle];
        NSString* myFile = [mainBundle pathForResource: @"opensource" ofType: @"html"];

        [web initViewWithUrl:[NSURL fileURLWithPath:myFile]];
    }
    else if([segue.identifier isEqualToString:@"showAbout"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        [web initViewWithUrl:[NSURL URLWithString:@"https://monal-im.org/about"]];
    }
    else if([segue.identifier isEqualToString:@"showPrivacy"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        [web initViewWithUrl:[NSURL URLWithString:@"https://monal-im.org/privacy"]];
    }
    else if([segue.identifier isEqualToString:@"showBug"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        [web initViewWithUrl:[NSURL URLWithString:@"https://github.com/monal-im/Monal/issues"]];
    }
    else if([segue.identifier isEqualToString:@"showFAQ"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        [web initViewWithUrl:[NSURL URLWithString:@"https://github.com/monal-im/Monal/wiki/FAQ---Frequently-Asked-Questions"]];
    }
    else if([segue.identifier isEqualToString:@"editXMPP"])
    {
        XMPPEdit* editor = (XMPPEdit*) segue.destinationViewController.childViewControllers.firstObject; // segue.destinationViewController;

        if(self.selected && self.selected.row >= (int) [self getAccountNum])
        {
            editor.accountID = [NSNumber numberWithInt:-1];
        }
        else
        {
            MLAssert(self.selected != nil, @"self.selected must not be nil");
            editor.originIndex = self.selected;
            editor.accountID = [self getAccountIDByIndex:self.selected.row];
        }
    }
}

//VELO: icona su quadratino colorato, come le schede della Velo Android
-(UIImage*) veloIcon:(NSString*) symbol color:(UIColor*) color
{
    CGSize size = CGSizeMake(30, 30);
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext* ctx __unused) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:8] fill];
        UIImageSymbolConfiguration* config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        UIImage* glyph = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        if(glyph != nil)
            [glyph drawInRect:CGRectMake((size.width - glyph.size.width) / 2, (size.height - glyph.size.height) / 2, glyph.size.width, glyph.size.height)];
    }];
}

-(UITableViewCell*) veloCellTitle:(NSString*) title summary:(NSString*) summary symbol:(NSString*) symbol color:(UIColor*) color
{
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = summary;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [self veloIcon:symbol color:color];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

-(UIColor*) veloRGB:(uint32_t) rgb
{
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    switch((int)indexPath.section)
    {
        case kSettingSectionLook:
            return [self veloCellTitle:@"Aspetto" summary:@"Tema, colori, sfondo delle chat, dimensione del testo" symbol:@"hand.tap.fill" color:[self veloRGB:0x7E57C2]];
        case kSettingSectionMain:
            switch(indexPath.row) {
                case VeloPrivacyRow:
                    return [self veloCellTitle:@"Privacy" summary:@"Conferme di lettura, sta scrivendo, ultimo accesso" symbol:@"info.circle.fill" color:[self veloRGB:0x1E88E5]];
                case VeloSecurityRow:
                    return [self veloCellTitle:@"Sicurezza" summary:@"Blocco dell'app, PIN antipanico, cancellazione automatica" symbol:@"checkmark.shield.fill" color:[self veloRGB:0x43A047]];
                case VeloNotificationsRow:
                    return [self veloCellTitle:@"Notifiche" summary:@"Cosa mostrano le notifiche" symbol:@"bell.fill" color:[self veloRGB:0xE53935]];
                case SoundsRow:
                    return [self veloCellTitle:@"Suoni" summary:@"Suono dei messaggi in arrivo" symbol:@"speaker.wave.2.fill" color:[self veloRGB:0xD81B60]];
                default:
                    unreachable();
            }
            break;
        case kSettingSectionData:
            switch(indexPath.row) {
                case VeloAttachmentsRow:
                    return [self veloCellTitle:@"Dati e media" summary:@"Download automatico, qualità di foto e video" symbol:@"paperclip" color:[self veloRGB:0xFB8C00]];
                case VeloDiagnosticsRow:
                    return [self veloCellTitle:@"Diagnostica connessione" summary:@"Stato di Tor e degli account" symbol:@"chevron.left.forwardslash.chevron.right" color:[self veloRGB:0x546E7A]];
                case GeneralSettingsRow:
                    return [self veloCellTitle:@"Impostazioni avanzate" summary:@"Tutte le altre opzioni" symbol:@"gearshape.fill" color:[self veloRGB:0x757575]];
                default:
                    unreachable();
            }
            break;
        default:
            break;
    }
    MLSwitchCell* cell = [tableView dequeueReusableCellWithIdentifier:@"AccountCell" forIndexPath:indexPath];
    switch((int)indexPath.section)
    {
        case kSettingSectionAccounts: {
            if(indexPath.row < (int) [self getAccountNum])
            {
                // User selected an account
                [self initContactCell:cell forAccNo:indexPath.row];
            }
            else
            {
                MLAssert(indexPath.row - [self getAccountNum] < SettingsAccountRowsCnt, @"Tried to tap onto a row meant to be for a concrete account, not for quick or advanced settings");
                
                // User selected one of the 'add account' promts
                switch(indexPath.row - [self getAccountNum]) {
                    case QuickSettingsRow:
                        [cell initTapCell:NSLocalizedString(@"Add Account", @"")];
                        break;
                    case AdvancedSettingsRow:
                        [cell initTapCell:NSLocalizedString(@"Add Account (advanced)", @"")];
                        break;
                    default:
                        unreachable();
                }
            }
            break;
        }
        case kSettingSectionSupport: {
            switch(indexPath.row) {
                case EmailRow:
                    [cell initTapCell:NSLocalizedString(@"Email Support", @"")];
                    break;
                case SubmitABugRow:
                    [cell initTapCell:NSLocalizedString(@"Submit A Bug", @"")];
                    break;
                case OpenFAQRow:
                    [cell initTapCell:NSLocalizedString(@"Frequently Asked Questions", @"")];
                    break;
                default:
                    unreachable();
            }
            break;
        }
        case kSettingSectionAbout: {
            switch(indexPath.row) {
                case RateMonalRow: {
                    [cell initTapCell:NSLocalizedString(@"Rate Monal", @"")];
                    break;
                }
                case OpenSourceRow: {
                    [cell initTapCell:NSLocalizedString(@"Open Source", @"")];
                    break;
                }
                case PrivacyRow: {
                    [cell initTapCell:NSLocalizedString(@"Privacy", @"")];
                    break;
                }
                case AboutRow: {
                    [cell initTapCell:NSLocalizedString(@"About", @"")];
                    break;
                }
                case VersionRow: {
                    [cell initCell:NSLocalizedString(@"Version", @"") withLabel:[HelperTools appBuildVersionInfoFor:MLVersionTypeIQ]];
                    break;
                }
#ifdef DEBUG
                case LogRow:
#endif
                case SettingsAboutRowsCntORLogRow: {
                    [cell initTapCell:NSLocalizedString(@"Debug", @"")];
                    break;
                }
                default: {
                    unreachable();
                }
            }
            break;
        }
        default:
            unreachable();
    }
    cell.hidden = (indexPath.section == kSettingSectionAbout && (indexPath.row == RateMonalRow || indexPath.row == PrivacyRow || indexPath.row == AboutRow));
    return cell;
}

//VELO: "Valuta", "Privacy" e "Informazioni" erano di Monal (App Store e siti fuori da Tor): righe nascoste
-(CGFloat) tableView:(UITableView*) tableView heightForRowAtIndexPath:(NSIndexPath*) indexPath
{
    if(indexPath.section == kSettingSectionAbout && (indexPath.row == RateMonalRow || indexPath.row == PrivacyRow || indexPath.row == AboutRow))
        return 0;
    return UITableViewAutomaticDimension;
}

-(NSString*) tableView:(UITableView*) tableView titleForHeaderInSection:(NSInteger) section
{
    switch(section) {
        case kSettingSectionAccounts:
            return nil;             //the account section does not need a heading (its the first one)
        case kSettingSectionLook:
        case kSettingSectionMain:
        case kSettingSectionData:
            return nil;             //VELO: schede senza titolo, come la Android
        case kSettingSectionSupport:
            return nil;
        case kSettingSectionAbout:
            return @"Informazioni su Velo";
        default:
            unreachable();
    }
    return nil;     //needed to make the compiler happy
}

-(void)tableView:(UITableView*) tableView didSelectRowAtIndexPath:(NSIndexPath*) indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.section == kSettingSectionSupport || (indexPath.section == kSettingSectionAbout && (indexPath.row == RateMonalRow || indexPath.row == PrivacyRow || indexPath.row == AboutRow)))
        return;
    switch(indexPath.section)
    {
        case kSettingSectionAccounts: {
            self.selected = indexPath;
            if(indexPath.row < (int) [self getAccountNum])
                [self performSegueWithIdentifier:@"editXMPP" sender:self];
            else
            {
                switch(indexPath.row - [self getAccountNum]) {
                    case QuickSettingsRow: {
                        UIViewController* loginView = [[SwiftuiInterface new] makeViewWithName:@"LogIn"];
                        [self showDetailViewController:loginView sender:self];
                        break;
                    }
                    case AdvancedSettingsRow: {
                        UIViewController* advancedLoginView = [[SwiftuiInterface new] makeViewWithName:@"AdvancedLogIn"];
                        [self showDetailViewController:advancedLoginView sender:self];
                        break;
                    }
                    default:
                        unreachable();
                }
            }
            break;
        }
        case kSettingSectionLook: {
            [self showDetailViewController:[[SwiftuiInterface new] makeViewWithName:@"VeloAppearance"] sender:self];
            break;
        }
        case kSettingSectionMain: {
            switch(indexPath.row) {
                    
                case VeloPrivacyRow:
                    [self showDetailViewController:[[SwiftuiInterface new] makeViewWithName:@"VeloPrivacy"] sender:self];
                    break;
                case VeloSecurityRow:
                    [self showDetailViewController:[[SwiftuiInterface new] makeViewWithName:@"VeloSecurity"] sender:self];
                    break;
                case VeloNotificationsRow:
                    [self showDetailViewController:[[SwiftuiInterface new] makeViewWithName:@"VeloNotifications"] sender:self];
                    break;
                case SoundsRow:
                    [self performSegueWithIdentifier:@"showSounds" sender:self];
                    break;
                default:
                    unreachable();
            }
            break;
        }
        case kSettingSectionData: {
            switch(indexPath.row) {
                case VeloAttachmentsRow:
                    [self showDetailViewController:[[SwiftuiInterface new] makeViewWithName:@"VeloAttachments"] sender:self];
                    break;
                case VeloDiagnosticsRow:
                    [self showDetailViewController:[[SwiftuiInterface new] makeViewWithName:@"VeloDiagnostics"] sender:self];
                    break;
                case GeneralSettingsRow:
                    [self showDetailViewController:[[SwiftuiInterface new] makeViewWithName:@"GeneralSettings"] sender:self];
                    break;
                default:
                    unreachable();
            }
            break;
        }
        case kSettingSectionSupport: {
            switch(indexPath.row) {
                case EmailRow:
                    [self composeMail];
                    break;
                case SubmitABugRow:
                    [self performSegueWithIdentifier:@"showBug" sender:self];
                    break;
                case OpenFAQRow:
                    [self performSegueWithIdentifier:@"showFAQ" sender:self];
                    break;
                default:
                    unreachable();
            }
            break;
        }
        case kSettingSectionAbout: {
            switch(indexPath.row) {
                case RateMonalRow:
#if TARGET_OS_MACCATALYST
                    [self openStoreProductViewControllerWithITunesItemIdentifier:1637078500];
#else
                    [self openStoreProductViewControllerWithITunesItemIdentifier:317711500];
#endif
                    break;
                case OpenSourceRow:
                    [self performSegueWithIdentifier:@"showOpenSource" sender:self];
                    break;
                case PrivacyRow:
                    [self performSegueWithIdentifier:@"showPrivacy" sender:self];
                    break;
                case AboutRow:
                    [self performSegueWithIdentifier:@"showAbout" sender:self];
                    break;
#ifdef DEBUG
                case LogRow:
#endif
                case SettingsAboutRowsCntORLogRow:{
                    UIViewController* logView = [[SwiftuiInterface new] makeViewWithName:@"DebugView"];
                    [self showDetailViewController:logView sender:self];
                    break;
                }
                case VersionRow: {
#ifndef DEBUG
                    if(_tappedVersionInfo >= 16)
                    {
                        [[HelperTools defaultsDB] setBool:YES forKey:@"showLogInSettings"];
                        [tableView reloadData];
                    }
                    else
                        _tappedVersionInfo++;
#endif
                    UIPasteboard* pastboard = UIPasteboard.generalPasteboard;
                    pastboard.string = [HelperTools appBuildVersionInfoFor:MLVersionTypeIQ];
                    break;
                }
                default:
                    unreachable();
            }
            break;
        }
        default:
            unreachable();
    }
}

-(void) openLink:(NSString *) link
{
    NSURL* url = [NSURL URLWithString:link];
    
    if ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"]) {
        SFSafariViewController* safariView = [[ SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safariView animated:YES completion:nil];
    }
}

#pragma mark - Actions


-(void) openStoreProductViewControllerWithITunesItemIdentifier:(NSInteger) iTunesItemIdentifier {
    SKStoreProductViewController *storeViewController = [SKStoreProductViewController new];
    
    storeViewController.delegate = self;
    
    NSNumber* identifier = [NSNumber numberWithInteger:iTunesItemIdentifier];
    //, @"action":@"write-review"
    NSDictionary* parameters = @{ SKStoreProductParameterITunesItemIdentifier:identifier};
    
    [storeViewController loadProductWithParameters:parameters
                                   completionBlock:^(BOOL result, NSError *error) {
                                       if (result)
                                           [self presentViewController:storeViewController
                                                              animated:YES
                                                            completion:nil];
                                       else NSLog(@"SKStoreProductViewController: %@", error);
                                   }];
    
    
}

-(void) composeMail
{
    if([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController* composeVC = [MFMailComposeViewController new];
        composeVC.mailComposeDelegate = self;
        [composeVC setToRecipients:@[@"info@monal-im.org"]];
        [self presentViewController:composeVC animated:YES completion:nil];
    }
    else
    {
        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"") message:NSLocalizedString(@"There is no configured email account. Please email info@monal-im.org .", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
        }];
        [messageAlert addAction:closeAction];
        
        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    
}

#pragma mark - Message ui delegate
- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error
{
    [controller dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - SKStoreProductViewControllerDelegate

-(void)productViewControllerDidFinish:(SKStoreProductViewController *)viewController {
    [viewController dismissViewControllerAnimated:YES completion:nil];
}
@end

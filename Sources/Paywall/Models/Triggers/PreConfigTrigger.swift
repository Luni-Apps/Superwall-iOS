//
//  File.swift
//  
//
//  Created by Yusuf Tör on 01/06/2022.
//

import UIKit

struct PreConfigTrigger {
  let presentationInfo: PresentationInfo
  var presentationStyleOverride: PaywallPresentationStyle?
  var viewController: UIViewController?
  var ignoreSubscriptionStatus = false
  var onSkip: PaywallSkippedCompletionBlock?
  var onPresent: ((PaywallInfo) -> Void)?
  var onDismiss: PaywallDismissedCompletionBlock?
}

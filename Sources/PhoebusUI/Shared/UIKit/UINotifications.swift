import Foundation

/// Notification names posted across views in PhoebusUI.
extension Notification.Name {
    /// Posted to collapse an expanded navigation action group. The
    /// notification's `object` carries the real
    /// `NavigationActionsPolicy.CollapseReason`, which decides whether
    /// the collapse animates.
    public static let apolloNavigationActionsCollapse = Notification.Name("apollo.navigationActions.collapse")

    /// Posted by any scrollable content that wants to participate in
    /// the Liquid Glass tab bar's hide-on-scroll behavior. Optional: a
    /// screen that never posts either notification simply never
    /// minimizes the pill.
    public static let apolloScrollDidScrollDown = Notification.Name("ApolloScrollDidScrollDown")
    public static let apolloScrollDidScrollUp = Notification.Name("ApolloScrollDidScrollUp")

    /// Posted when a tab becomes selected in the Liquid Glass tab bar,
    /// standing in for the `.onAppear` a real `TabView` would send.
    public static let apolloTabDidReappear = Notification.Name("apollo.tabDidReappear")
}

//
// Copyright © 2026 Stream.io Inc. All rights reserved.
//

import SwiftUI

/// View for the message actions.
/// Кнопка листа выбора: длинное имя типа не помещается в замыкание построителя.
private typealias ActionSheetButton = ActionSheet.Button

public struct MessageActionsView: View {
    @Injected(\.colors) private var colors

    @StateObject var viewModel: MessageActionsViewModel
    var bundle: Bundle?

    public init(
        messageActions: [MessageAction],
        bundle: Bundle? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ViewModelsFactory
                .makeMessageActionsViewModel(messageActions: messageActions)
        )
        self.bundle = bundle
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.messageActions) { action in
                VStack(spacing: 0) {
                    if let destination = action.navigationDestination {
                        NavigationLink {
                            destination
                        } label: {
                            ActionItemView(
                                title: action.title,
                                iconName: action.iconName,
                                isDestructive: action.isDestructive,
                                boldTitle: false,
                                bundle: bundle
                            )
                        }
                    } else {
                        Button {
                            if !action.reasonOptions.isEmpty {
                                viewModel.reasonAction = action
                            } else if action.confirmationPopup != nil {
                                viewModel.alertAction = action
                            } else {
                                action.action()
                            }
                        } label: {
                            ActionItemView(
                                title: action.title,
                                iconName: action.iconName,
                                isDestructive: action.isDestructive,
                                boldTitle: false,
                                bundle: bundle
                            )
                        }
                    }

                    Divider()
                }
                .padding(.leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("messageAction-\(action.id)")
            }
        }
        .background(Color(colors.background8))
        .roundWithBorder(cornerRadius: 12)
        .alert(isPresented: $viewModel.alertShown) {
            let title = viewModel.alertAction?.confirmationPopup?.title ?? ""
            let message = viewModel.alertAction?.confirmationPopup?.message ?? ""
            let buttonTitle = viewModel.alertAction?.confirmationPopup?.buttonTitle ?? ""

            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: .destructive(Text(buttonTitle)) {
                    viewModel.alertAction?.action()
                },
                secondaryButton: .cancel()
            )
        }
        // Причина уходит вместе с жалобой: менеджер видит её в админке.
        // actionSheet, а не confirmationDialog: приложение поддерживает iOS 14
        .actionSheet(isPresented: $viewModel.reasonShown) {
            let action = viewModel.reasonAction
            var buttons: [ActionSheetButton] = (action?.reasonOptions ?? []).map { reason in
                .default(Text(reason)) { action?.reasonAction?(reason) }
            }
            buttons.append(.cancel(Text(L10n.Alert.Actions.cancel)))
            return ActionSheet(title: Text(action?.title ?? ""), buttons: buttons)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MessageActionsView")
    }
}

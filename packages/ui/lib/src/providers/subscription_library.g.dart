// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscription_library.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SubscriptionLibrary)
final subscriptionLibraryProvider = SubscriptionLibraryProvider._();

final class SubscriptionLibraryProvider
    extends $NotifierProvider<SubscriptionLibrary, SubscriptionState> {
  SubscriptionLibraryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'subscriptionLibraryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$subscriptionLibraryHash();

  @$internal
  @override
  SubscriptionLibrary create() => SubscriptionLibrary();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SubscriptionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SubscriptionState>(value),
    );
  }
}

String _$subscriptionLibraryHash() =>
    r'f435f532a219bd18bce2d35c6ec40cc9081b69f7';

abstract class _$SubscriptionLibrary extends $Notifier<SubscriptionState> {
  SubscriptionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SubscriptionState, SubscriptionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SubscriptionState, SubscriptionState>,
              SubscriptionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

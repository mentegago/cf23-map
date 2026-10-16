import '../../services/deep_link_handler.dart';
import '../../services/search_tracking_controller.dart';
import 'package:cf_map_flutter/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/creator.dart';
import '../../services/creator_data_service.dart';
import '../creator_detail_content.dart';
import '../creator_list_view.dart';
import '../../design_system/cf_design_system.dart';

class DesktopSidebar extends StatefulWidget {
  final List<Creator> creators;
  final Creator? selectedCreator;
  final void Function(Creator, {required String source, String searchQuery})
      onCreatorSelected;
  final VoidCallback? onClear;
  final VoidCallback? onCreatorDismissed;

  const DesktopSidebar({
    super.key,
    required this.creators,
    this.selectedCreator,
    required this.onCreatorSelected,
    this.onClear,
    this.onCreatorDismissed,
  });

  @override
  State<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<DesktopSidebar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _searchScrollController = ScrollController();
  bool _showSearchList = true;

  @override
  void initState() {
    super.initState();

    _searchFocusNode.addListener(() {
      if (mounted && _searchFocusNode.hasFocus) {
        context.read<AnalyticsService>().searchOpened();
        context.read<AnalyticsService>().creatorClosed(reason: 'search_opened');
        setState(() {
          _showSearchList = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(DesktopSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedCreator != null &&
        widget.selectedCreator != oldWidget.selectedCreator &&
        _showSearchList) {
      setState(() {
        _showSearchList = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchScrollController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (_searchScrollController.hasClients) _searchScrollController.jumpTo(0);
  }

  void _handleCreatorSelected(Creator creator) {
    setState(() {
      _showSearchList = false;
    });
    widget.onCreatorSelected(creator,
        source: 'list', searchQuery: _searchController.text);
  }

  void _handleRecommendationSelected(Creator creator) {
    setState(() {
      _showSearchList = false;
    });
    widget.onCreatorSelected(creator, source: 'recommendation');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: context.cf.paperRaised,
        border: Border(
          right: BorderSide(
            color: context.cf.ink,
            width: 2,
          ),
        ),
      ),
      child: Column(
        children: [
          // Search section
          Container(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CfKicker('CF23 creator directory'),
                const SizedBox(height: 10),
                _buildSearchField(context, theme, isDark),
              ],
            ),
          ),

          // Content section
          Expanded(
            child: IndexedStack(
              index: widget.selectedCreator != null && !_showSearchList ? 0 : 1,
              children: [
                _buildCreatorDetail(context, theme),
                _buildCreatorList(context, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: context.cf.paper,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(5),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: context.cf.ink, width: 1.5),
        boxShadow: [
          BoxShadow(color: context.cf.cyan, offset: const Offset(3, 3))
        ],
      ),
      child: Row(
        children: [
          if (widget.selectedCreator != null)
            // Dismiss selected creator
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                /*
                  On creator detail page, it dismisses the creator detail page
                  On search results page, it goes back to creator detail page (if a creator is still selected)
                */
                if (!_showSearchList) {
                  widget.onCreatorDismissed?.call();
                } else {
                  context.read<AnalyticsService>().searchClosed(reason: 'back');
                  context.read<AnalyticsService>().creatorOpened(
                      widget.selectedCreator!.id, SelectionSource.list);
                  setState(() {
                    _showSearchList = false;
                  });
                }
              },
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Icon(Icons.search, color: context.cf.pink),
            ),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: const InputDecoration(
                hintText: 'Search name, booth, or fandom...',
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (query) {
                context.read<SearchTrackingController>().changed(query);
                _performSearch(query);
              },
              onSubmitted: _handleSearchSubmitted,
            ),
          ),
          // Show clear search button if search field is not empty
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              if (value.text.isNotEmpty) {
                return IconButton(
                  icon: Icon(Icons.close,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      size: 20),
                  onPressed: () {
                    context.read<AnalyticsService>().searchCleared();
                    context.read<SearchTrackingController>().reset();
                    _searchController.clear();
                    widget.onClear?.call();
                    _performSearch('');
                  },
                );
              } else if (widget.selectedCreator != null) {
                return IconButton(
                  icon: Icon(Icons.close,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      size: 20),
                  onPressed: () {
                    context.read<AnalyticsService>().searchCleared();
                    context.read<SearchTrackingController>().reset();
                    widget.onClear?.call();
                  },
                );
              } else {
                return const SizedBox(width: 8);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorList(BuildContext context, ThemeData theme) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchController,
      builder: (context, value, _) {
        return CreatorListView(
          creators: widget.creators,
          searchQuery: value.text,
          onCreatorSelected: _handleCreatorSelected,
          onRecommendationSelected: _handleRecommendationSelected,
          scrollController: _searchScrollController,
          homeVisible: widget.selectedCreator == null || _showSearchList,
          onShouldHideListScreen: () {},
          onClearSearch: () {
            context.read<SearchTrackingController>().reset();
            _searchController.clear();
            _performSearch('');
          },
          onSearchQueryChanged: (query) {
            _searchController.text = query;
            _performSearch(query);
          },
        );
      },
    );
  }

  Widget _buildCreatorDetail(BuildContext context, ThemeData theme) {
    final creator = widget.selectedCreator;
    if (creator == null) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      child: CreatorDetailContent(
        creator: creator,
        showShareButton: true,
        showFavoriteButton: true,
        showCloseButton: false,
        onRequestSearch: _handleRequestSearch,
      ),
    );
  }

  void _handleRequestSearch(String query) {
    context.read<AnalyticsService>().creatorClosed(reason: 'search_opened');
    setState(() {
      _searchController.text = query;
      _showSearchList = true;
    });

    _performSearch(query);
  }

  void _handleSearchSubmitted(String text) {
    final tracking = context.read<SearchTrackingController>();
    tracking.submit(text);
    final handled = applyDeepLink(
        text,
        context.read<CreatorDataProvider>(),
        context.read<AnalyticsService>(),
        (creator) => widget.onCreatorSelected(creator, source: 'deeplink'));
    if (handled) {
      tracking.reset();
      _searchController.clear();
      _performSearch('');
    }
  }
}

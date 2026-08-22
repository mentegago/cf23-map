import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/creator.dart';
import '../../services/analytics_service.dart';
import '../../services/creator_data_service.dart';
import '../../services/recommendation_service.dart';
import '../../utils/fuzzy_score.dart';
import '../../utils/int_encoding.dart';
import '../../utils/string_utils.dart';
import '../creator_list_view.dart';
import 'mobile_sheet_detent.dart';

class ExpandableSearch extends StatefulWidget {
  final List<Creator> creators;
  final void Function(
    Creator, {
    required String source,
    String searchQuery,
  }) onCreatorSelected;
  final VoidCallback? onClear;
  final Creator? selectedCreator;

  const ExpandableSearch({
    super.key,
    required this.creators,
    required this.onCreatorSelected,
    this.onClear,
    this.selectedCreator,
  });

  @override
  State<ExpandableSearch> createState() => ExpandableSearchState();
}

class ExpandableSearchState extends State<ExpandableSearch> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  ScrollController? _activeScrollController;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  MobileSheetDetent _detent = MobileSheetDetent.collapsed;
  double _extent = MobileSheetDetent.collapsed.extent;
  double? _dragStartExtent;

  MobileSheetDetent get currentDetent => _sheetController.isAttached
      ? MobileSheetDetent.nearest(_sheetController.size)
      : _detent;

  Future<void> animateToDetent(MobileSheetDetent detent) async {
    _detent = detent;
    if (!_sheetController.isAttached) return;
    await _sheetController.animateTo(
      detent.extent,
      duration: mobileSheetAnimationDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void jumpToDetent(MobileSheetDetent detent) {
    _detent = detent;
    _extent = detent.extent;
    if (_sheetController.isAttached) {
      _sheetController.jumpTo(detent.extent);
    }
  }

  void performSearch(String query) {
    setState(() {
      _searchController.text = query;
    });
    _performSearch(query);
    animateToDetent(MobileSheetDetent.expanded);
  }

  void expandIfSearching() {
    if (_searchController.text.isNotEmpty) {
      animateToDetent(MobileSheetDetent.expanded);
    }
  }

  @override
  void initState() {
    super.initState();

    _sheetController.addListener(_handleExtentChanged);
    _focusNode.addListener(() {
      if (mounted &&
          _focusNode.hasFocus &&
          currentDetent != MobileSheetDetent.expanded) {
        umami.trackEvent(name: 'search_bar_opened');
        context.read<RecommendationService>().startNewRecommendationSession();
        animateToDetent(MobileSheetDetent.expanded);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _sheetController
      ..removeListener(_handleExtentChanged)
      ..dispose();
    super.dispose();
  }

  void _handleExtentChanged() {
    if (!mounted || !_sheetController.isAttached) return;
    final extent = _sheetController.size;
    final detent = MobileSheetDetent.nearest(extent);
    if ((_extent - extent).abs() > 0.001 || _detent != detent) {
      setState(() {
        _extent = extent;
        _detent = detent;
      });
    }
  }

  void _performSearch(String query) {
    if (_activeScrollController?.hasClients ?? false) {
      _activeScrollController!.jumpTo(0);
    }
  }

  void _collapse() {
    _focusNode.unfocus();
    animateToDetent(MobileSheetDetent.collapsed);
  }

  void _handleCreatorTap(Creator creator) {
    _focusNode.unfocus();
    widget.onCreatorSelected(
      creator,
      source: 'list',
      searchQuery: _searchController.text,
    );
  }

  void _handleRecommendationTap(Creator creator) {
    _focusNode.unfocus();
    widget.onCreatorSelected(creator, source: 'recommendation');
  }

  void _handleClear() {
    umami.trackEvent(
      name: 'search_bar_clear_tapped',
      data: {
        'search_query': _searchController.text,
        'creator_id': widget.selectedCreator?.id.toString(),
        'creator_name': widget.selectedCreator?.name,
      },
    );
    setState(() {
      _searchController.clear();
    });
    _collapse();
    widget.onClear?.call();
  }

  void _handleSearchSubmitted(String text) {
    // Router function - delegates to specific handlers based on URL pattern
    if (text.contains('?list=')) {
      _handleListUrl(text);
    } else if (text.contains('?creator_id=')) {
      _handleCreatorIdUrl(text);
    } else if (text.contains('?creator=')) {
      _handleCreatorUrl(text);
    } else if (text.contains('?custom_list=')) {
      _handleCustomListUrl(text);
    }
  }

  void _handleListUrl(String text) {
    try {
      // Parse the URL
      final uri = Uri.tryParse(text);
      if (uri == null) {
        return; // Invalid URL, fail silently
      }

      // Extract the list query parameter
      final listParam = uri.queryParameters['list'];
      if (listParam == null || listParam.isEmpty) {
        return; // No list parameter, fail silently
      }

      // Decode the compressed list
      final idList = IntEncoding.stringCodeToInts(listParam);
      if (idList.isEmpty) {
        return; // Empty or invalid list, fail silently
      }

      // Set creator custom list with specified flags
      final creatorProvider = context.read<CreatorDataProvider>();
      creatorProvider.setCreatorCustomList(
        idList,
        showAddAllToFavorites: true,
        shouldRefreshOnReturn: false,
      );

      // Clear search controller only on success
      setState(() {
        _searchController.clear();
      });
      _collapse();
    } catch (e) {
      // Fail silently on any error
      return;
    }
  }

  void _handleCreatorIdUrl(String text) {
    try {
      // Parse the URL
      final uri = Uri.tryParse(text);
      if (uri == null) {
        return; // Invalid URL, fail silently
      }

      // Extract the creator_id query parameter
      final creatorIdParam = uri.queryParameters['creator_id'];
      if (creatorIdParam == null || creatorIdParam.isEmpty) {
        return; // No creator_id parameter, fail silently
      }

      // Parse creator ID
      final creatorId = int.tryParse(creatorIdParam);
      if (creatorId == null) {
        return; // Invalid creator ID, fail silently
      }

      // Get creator by ID
      final creatorProvider = context.read<CreatorDataProvider>();
      final creator = creatorProvider.getCreatorById(creatorId);
      if (creator == null) {
        return; // Creator not found, fail silently
      }

      // Select the creator
      widget.onCreatorSelected(creator, source: 'deeplink');

      // Clear search controller only on success
      setState(() {
        _searchController.clear();
      });
      _collapse();
    } catch (e) {
      // Fail silently on any error
      return;
    }
  }

  void _handleCreatorUrl(String text) {
    try {
      // Parse the URL
      final uri = Uri.tryParse(text);
      if (uri == null) {
        return; // Invalid URL, fail silently
      }

      // Extract the creator query parameter
      final creatorParam = uri.queryParameters['creator'];
      if (creatorParam == null || creatorParam.isEmpty) {
        return; // No creator parameter, fail silently
      }

      // Decode and normalize name (replace + with space, trim)
      final searchName = Uri.decodeComponent(creatorParam.replaceAll('+', ' '))
          .trim()
          .toLowerCase();
      if (searchName.isEmpty) {
        return; // Empty search name, fail silently
      }

      // Get all creators from provider
      final creatorProvider = context.read<CreatorDataProvider>();
      final creators = creatorProvider.creators;
      if (creators == null || creators.isEmpty) {
        return; // No creators available, fail silently
      }

      // Find creator by name (case-insensitive, partial match)
      Creator? creator;
      try {
        creator = creators.firstWhere(
          (c) => c.name.toLowerCase().contains(searchName),
          orElse: () => creators.firstWhere(
            (c) => c.name.toLowerCase() == searchName,
            orElse: () =>
                creators.first, // fallback, won't be used if null check below
          ),
        );

        // Only select if we found a match
        if (!creator.name.toLowerCase().contains(searchName)) {
          return; // No match found, fail silently
        }
      } catch (e) {
        return; // No match found, fail silently
      }

      // Select the creator
      widget.onCreatorSelected(creator, source: 'deeplink');

      // Clear search controller only on success
      setState(() {
        _searchController.clear();
      });
      _collapse();
    } catch (e) {
      // Fail silently on any error
      return;
    }
  }

  void _handleCustomListUrl(String text) {
    try {
      // Parse the URL
      final uri = Uri.tryParse(text);
      if (uri == null) {
        return; // Invalid URL, fail silently
      }

      // Extract the custom_list query parameter
      final customListParam = uri.queryParameters['custom_list'];
      if (customListParam == null || customListParam.isEmpty) {
        return; // No custom_list parameter, fail silently
      }

      // Parse comma-separated creator IDs
      final idStrings = customListParam.split(',');
      final idList = idStrings
          .map((idStr) => int.tryParse(idStr.trim()))
          .where((id) => id != null)
          .cast<int>()
          .toList();

      if (idList.isEmpty) {
        return; // Empty or invalid list, fail silently
      }

      // Set creator custom list with specified flags
      final creatorProvider = context.read<CreatorDataProvider>();
      creatorProvider.setCreatorCustomList(
        idList,
        showAddAllToFavorites: true,
        shouldRefreshOnReturn: false,
      );

      // Clear search controller only on success
      setState(() {
        _searchController.clear();
      });
      _collapse();
    } catch (e) {
      // Fail silently on any error
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final contentOpacity = ((_extent - MobileSheetDetent.collapsed.extent) /
            (MobileSheetDetent.partiallyExpanded.extent -
                MobileSheetDetent.collapsed.extent))
        .clamp(0.0, 1.0);

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: MobileSheetDetent.collapsed.extent,
      minChildSize: MobileSheetDetent.collapsed.extent,
      maxChildSize: MobileSheetDetent.expanded.extent,
      snap: true,
      snapSizes: [MobileSheetDetent.partiallyExpanded.extent],
      snapAnimationDuration: mobileSheetAnimationDuration,
      shouldCloseOnMinExtent: false,
      builder: (context, sheetScrollController) {
        _activeScrollController = sheetScrollController;
        return LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    _buildSheetHeader(
                      context,
                      isDark: isDark,
                      availableHeight: constraints.maxHeight /
                          (_sheetController.isAttached
                              ? _sheetController.size
                              : _extent),
                    ),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: contentOpacity < 0.95,
                        child: Opacity(
                          opacity: contentOpacity,
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, value, _) {
                              return CreatorListView(
                                creators: widget.creators,
                                searchQuery: value.text,
                                onCreatorSelected: _handleCreatorTap,
                                onRecommendationSelected:
                                    _handleRecommendationTap,
                                scrollController: sheetScrollController,
                                onShouldHideListScreen: _collapse,
                                onClearSearch: () {
                                  _searchController.clear();
                                  _performSearch('');
                                },
                                onSearchQueryChanged: (query) {
                                  _searchController.text = query;
                                  _performSearch(query);
                                },
                                showFandomSuggestions: false,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetHeader(
    BuildContext context, {
    required bool isDark,
    required double availableHeight,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _dragStartExtent =
            _sheetController.isAttached ? _sheetController.size : _extent;
      },
      onVerticalDragUpdate: (details) {
        if (!_sheetController.isAttached || _dragStartExtent == null) return;
        final next =
            (_dragStartExtent! - details.primaryDelta! / availableHeight).clamp(
                MobileSheetDetent.collapsed.extent,
                MobileSheetDetent.expanded.extent);
        _dragStartExtent = next;
        _sheetController.jumpTo(next);
      },
      onVerticalDragEnd: (details) {
        if (!_sheetController.isAttached) return;
        final velocity = details.primaryVelocity ?? 0;
        final current = _sheetController.size;
        MobileSheetDetent target;
        if (velocity < -500) {
          target = MobileSheetDetent.values.firstWhere(
            (value) => value.extent > current + 0.01,
            orElse: () => MobileSheetDetent.expanded,
          );
        } else if (velocity > 500) {
          target = MobileSheetDetent.values.reversed.firstWhere(
            (value) => value.extent < current - 0.01,
            orElse: () => MobileSheetDetent.collapsed,
          );
        } else {
          target = MobileSheetDetent.nearest(current);
        }
        _dragStartExtent = null;
        animateToDetent(target);
      },
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                if (_extent > MobileSheetDetent.collapsed.extent + 0.02)
                  IconButton(
                    tooltip: 'Collapse search',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      umami.trackEvent(
                        name: 'search_bar_back_tapped',
                        data: {
                          'search_query': _searchController.text,
                          'creator_id': widget.selectedCreator?.id.toString(),
                          'creator_name': widget.selectedCreator?.name,
                        },
                      );
                      _collapse();
                    },
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Icon(Icons.search, color: Colors.grey),
                  ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      hintText: 'Search name, booth, or fandom...',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: _performSearch,
                    onSubmitted: _handleSearchSubmitted,
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    if (value.text.isNotEmpty || widget.onClear != null) {
                      return IconButton(
                        tooltip: 'Clear search',
                        icon: Icon(
                          Icons.close,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                          size: 20,
                        ),
                        onPressed: _handleClear,
                      );
                    }
                    return const SizedBox(width: 8);
                  },
                ),
              ],
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              final suggestions = _headerFandomSuggestions(context, value.text);
              if (suggestions.isEmpty) return const SizedBox(height: 48);
              return SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final fandom = suggestions[index];
                    return ActionChip(
                      label: Text(fandom, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        umami.trackEvent(
                          name: 'fandom_tapped',
                          data: {
                            'source': 'search_suggestion',
                            'fandom': fandom,
                          },
                        );
                        _searchController.text = fandom;
                        _performSearch(fandom);
                        _focusNode.requestFocus();
                      },
                      backgroundColor: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.5),
                      side: BorderSide(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  List<String> _headerFandomSuggestions(
    BuildContext context,
    String searchQuery,
  ) {
    final provider = context.read<CreatorDataProvider>();
    if (searchQuery.isEmpty &&
        !provider.isCreatorCustomListMode &&
        provider.popularSearches.isNotEmpty) {
      return provider.popularSearches;
    }

    final counts = <String, int>{};
    for (final creator in widget.creators) {
      for (final fandom in creator.fandoms) {
        counts[fandom] = (counts[fandom] ?? 0) + 1;
      }
    }
    if (searchQuery.isEmpty) {
      final entries = counts.entries.toList()
        ..sort((a, b) {
          final count = b.value.compareTo(a.value);
          return count != 0 ? count : a.key.compareTo(b.key);
        });
      return entries.take(20).map((entry) => entry.key).toList();
    }

    final query = optimizeStringFormat(searchQuery.trim().toLowerCase());
    final matches = counts.entries
        .map((entry) => (entry, fuzzyScore(query, entry.key.toLowerCase())))
        .where((match) => match.$2.matched && match.$2.score >= 0.7)
        .toList()
      ..sort((a, b) {
        final score = b.$2.score.compareTo(a.$2.score);
        if (score != 0) return score;
        final count = b.$1.value.compareTo(a.$1.value);
        return count != 0 ? count : a.$1.key.compareTo(b.$1.key);
      });
    return matches.take(20).map((match) => match.$1.key).toList();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/analytics_service.dart';
import '../services/creator_data_service.dart';
import '../models/recommendation.dart';
import '../services/recommendation_service.dart';
import '../design_system/cf_design_system.dart';

class FABButton extends StatelessWidget {
  const FABButton({super.key, required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final githubIcon =
        isDark ? 'assets/github-mark-white.svg' : 'assets/github-mark.svg';

    return Positioned(
      bottom: 16,
      left: isDesktop ? 16 : null,
      right: isDesktop ? null : 16,
      child: Row(
        children: [
          _randomButton(context),
          const SizedBox(width: 8),
          _githubButton(context, githubIcon),
        ],
      ),
    );
  }

  Widget _randomButton(BuildContext context) {
    return CfActionButton(
      label: 'Surprise me!',
      icon: Icons.auto_awesome,
      color: context.cf.yellow,
      onPressed: () {
        final creator =
            context.read<CreatorDataProvider>().selectRandomCreator();
        if (creator != null) {
          context.read<RecommendationService>().recordCreatorOpened(
                creator,
                CreatorSelectionSource.randomButton,
              );
          umami.trackEvent(
            name: 'creator_selected',
            data: {
              'creator_id': creator.id.toString(),
              'creator_name': creator.name,
              'source': 'surprise_fab',
            },
          );
        }
      },
    );
  }

  Widget _githubButton(BuildContext context, String githubIcon) {
    return Tooltip(
      message: 'View source on GitHub',
      child: CfPanel(
        borderRadius: 10,
        padding: const EdgeInsets.all(11),
        accent: context.cf.pink,
        onTap: () {
          umami.trackEvent(name: 'github_tapped');
          _launchGitHubUrl();
        },
        child: SvgPicture.asset(
          githubIcon,
          width: 22,
          height: 22,
        ),
      ),
    );
  }

  Future<void> _launchGitHubUrl() async {
    final url = Uri.parse('https://github.com/mentegago/cf23-map');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

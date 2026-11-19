import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Slide {
  const Slide(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

/// Shows [slides] once on first launch, then [child] forever after.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.slides, required this.color, required this.child});
  final List<Slide> slides;
  final Color color;
  final Widget child;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool? _seen;
  final _pages = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _seen = p.getBool('onboarded') ?? false);
    });
  }

  Future<void> _done() async {
    setState(() => _seen = true);
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarded', true);
  }

  @override
  Widget build(BuildContext context) {
    if (_seen == null) return const Scaffold();
    if (_seen!) return widget.child;
    final c = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final last = _page == widget.slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _done, child: const Text('Skip'))),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: widget.slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) {
                    final s = widget.slides[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 210,
                          height: 210,
                          decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Transform.rotate(
                            angle: -0.1,
                            child: Container(
                              width: 124,
                              height: 124,
                              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(36)),
                              child: Icon(s.icon, size: 60, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                        Text(s.title, textAlign: TextAlign.center, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        const SizedBox(height: 12),
                        Text(s.body, textAlign: TextAlign.center, style: text.bodyLarge?.copyWith(color: c.onSurfaceVariant, height: 1.5)),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(color: i == _page ? widget.color : c.outlineVariant, borderRadius: BorderRadius.circular(4)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: widget.color, minimumSize: const Size.fromHeight(56)),
                onPressed: last ? _done : () => _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                child: Text(last ? 'Get started' : 'Next', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

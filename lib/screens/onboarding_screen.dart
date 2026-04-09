import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildPage(Icons.bluetooth_searching, 'Connect to Bridge ESP',
                      'Scan and connect to your BLE-to-UART bridge device', Colors.blue),
                  _buildPage(Icons.qr_code_scanner, 'Scan Device QR Code',
                      'Use your camera to scan the QR code on Thread devices', Colors.green),
                  _buildPage(Icons.security, 'Secure Commissioning',
                      'Commands are signed with HMAC-SHA256 for security', Colors.purple),
                  _buildPage(Icons.history, 'Track Your Devices',
                      'View commission history and manage your Thread network', Colors.orange),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox(width: 80),
                  Row(
                    children: List.generate(
                      4,
                          (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _currentPage == 3
                        ? widget.onComplete
                        : () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    child: Text(_currentPage == 3 ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(IconData icon, String title, String description, Color color) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 120, color: color),
          const SizedBox(height: 48),
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(description,
              style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
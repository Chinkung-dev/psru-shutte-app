import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FavoriteStopsScreen extends StatefulWidget {
  const FavoriteStopsScreen({super.key});

  @override
  State<FavoriteStopsScreen> createState() => _FavoriteStopsScreenState();
}

class _FavoriteStopsScreenState extends State<FavoriteStopsScreen> {
  List<String> favoriteStops = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFavoriteStops();
  }

  Future<void> _fetchFavoriteStops() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && doc.data()!.containsKey('favorite_stops')) {
          if (mounted) {
            setState(() {
              favoriteStops = List<String>.from(doc.data()!['favorite_stops']);
              isLoading = false;
            });
          }
          return;
        }
      }
      if (mounted) setState(() => isLoading = false);
    } catch (e) {
      debugPrint("Error fetching favorite stops: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ฟังก์ชันเอาดาวออก และลบออกจาก Firestore ทันที
  Future<void> _removeFavorite(String stopName) async {
    setState(() {
      favoriteStops.remove(stopName);
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'favorite_stops': favoriteStops,
        });
      }
    } catch (e) {
      debugPrint("Error removing favorite stop: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF176a21)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'จุดจอดที่ใช้บ่อย',
          style: TextStyle(
            color: Color(0xFF176a21),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF176a21),
                  Color(0xFF66BB6A),
                  Color(0xFF9DF197),
                ],
              ),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF176a21),
              ),
            )
          : favoriteStops.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: favoriteStops.length,
                  itemBuilder: (context, index) {
                    final stopName = favoriteStops[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF176a21).withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF176a21).withOpacity(0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8F5E9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.hail_rounded,
                            color: Color(0xFF176a21),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          stopName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E2923),
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFB300),
                            size: 26,
                          ),
                          onPressed: () => _removeFavorite(stopName),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF176a21).withOpacity(0.12),
                ),
              ),
              child: const Icon(
                Icons.star_outline_rounded,
                size: 48,
                color: Color(0xFF176a21),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'ยังไม่มีจุดจอดที่ใช้บ่อย',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E2923),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'คุณสามารถเพิ่มได้โดยการกดที่ไอคอนดาว\nในช่องค้นหาจุดจอดรถ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF718076),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
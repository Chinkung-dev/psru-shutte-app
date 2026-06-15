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
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()!.containsKey('favorite_stops')) {
          setState(() {
            favoriteStops = List<String>.from(doc.data()!['favorite_stops']);
            isLoading = false;
          });
          return;
        }
      }
      setState(() => isLoading = false);
    } catch (e) {
      print("Error fetching favorite stops: $e");
      setState(() => isLoading = false);
    }
  }

  // ฟังก์ชันเอาดาวออก และลบออกจาก Firestore ทันที
  Future<void> _removeFavorite(String stopName) async {
    setState(() {
      favoriteStops.remove(stopName);
    });
    
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'favorite_stops': favoriteStops,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF176a21)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('จุดจอดที่ใช้บ่อย', style: TextStyle(color: Color(0xFF176a21), fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF176a21)))
          : favoriteStops.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: favoriteStops.length,
                  itemBuilder: (context, index) {
                    final stopName = favoriteStops[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: const Color(0xFF9DF197).withOpacity(0.3), shape: BoxShape.circle),
                          child: const Icon(Icons.location_on, color: Color(0xFF176a21), size: 20),
                        ),
                        title: Text(stopName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF2C2F30))),
                        trailing: IconButton(
                          icon: const Icon(Icons.star, color: Colors.amber, size: 26),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_border, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('ยังไม่มีจุดจอดที่ใช้บ่อย', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF595C5D))),
          const SizedBox(height: 8),
          const Text('คุณสามารถเพิ่มได้โดยการกดที่ไอคอนดาว\nในช่องค้นหาจุดจอดรถ', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5)),
        ],
      ),
    );
  }
}
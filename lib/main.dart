// lib/main.dart
//
// Chikandandi Blood Donors App
// Created By Kazi Sajid
//
// Firebase collections planned:
// donors
// donation_records
//
// Required packages:
// firebase_core
// cloud_firestore
// firebase_storage
// image_picker
// url_launcher
// google_fonts

import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final prefs = await SharedPreferences.getInstance();
  currentDonorId = prefs.getString('currentDonorId');

  runApp(const ChikandandiBloodDonorsApp());
}

class AppColors {
  static const Color deepRed = Color(0xFF8B0000);
  static const Color red = Color.fromARGB(255, 233, 27, 27);
  static const Color lightRed = Color(0xFFFFEBEE);
  static const Color white = Colors.white;
  static const Color dark = Color(0xFF242424);
  static const Color grey = Color(0xFF777777);
  static const Color green = Color(0xFF168A45);
}

class ChikandandiBloodDonorsApp extends StatelessWidget {
  const ChikandandiBloodDonorsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chikandandi Blood Donors',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF9F9F9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.deepRed,
          primary: AppColors.deepRed,
        ),
        textTheme: GoogleFonts.notoSansBengaliTextTheme(
          ThemeData.light().textTheme,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.deepRed,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          titleTextStyle: GoogleFonts.notoSansBengali(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

// ============================================================
// GLOBAL HELPERS
// ============================================================

final FirebaseFirestore db = FirebaseFirestore.instance;
final FirebaseStorage storage = FirebaseStorage.instance;

String? currentDonorId;

final ImagePicker imagePicker = ImagePicker();

Future<void> callNumber(String number) async {
  final Uri uri = Uri(scheme: 'tel', path: number);

  await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
}

String formatDate(DateTime? date) {
  if (date == null) return 'তারিখ নির্বাচন করুন';

  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}

DateTime? getLastDonationDate(Map<String, dynamic> data) {
  final value = data['lastDonationDate'];
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

DateTime getNextAvailableDate(DateTime donationDate) {
  return DateTime(
    donationDate.year,
    donationDate.month + 3,
    donationDate.day + 15,
  );
}

String getEffectiveAvailability(Map<String, dynamic> data) {
  final lastDonation = getLastDonationDate(data);
  if (lastDonation == null) {
    return data['availability'] ?? 'উপলব্ধ';
  }

  return DateTime.now().isBefore(getNextAvailableDate(lastDonation))
      ? 'অনুপলব্ধ'
      : 'উপলব্ধ';
}

Future<void> refreshDonorAvailability(
  String donorId,
  Map<String, dynamic> data,
) async {
  final lastDonation = getLastDonationDate(data);
  if (lastDonation == null) return;

  final effective = getEffectiveAvailability(data);
  if (data['availability'] != effective) {
    try {
      await db.collection('donors').doc(donorId).update({
        'availability': effective,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('AVAILABILITY UPDATE ERROR: $e');
    }
  }
}

String normalizeName(String value) => value.trim().toLowerCase();

String normalizePhone(String value) =>
    value.replaceAll(RegExp(r'\D'), '');

Future<String?> uploadImage(
  File file,
  String folder,
) async {
  try {
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';

    final ref = storage.ref().child(folder).child(fileName);

    await ref.putFile(file);

    final url = await ref.getDownloadURL();

    debugPrint('IMAGE UPLOAD SUCCESS: $url');

    return url;
  } catch (e) {
    debugPrint('IMAGE UPLOAD ERROR: $e');
    return null;
  }
}

Future<String?> profileImageToBase64(File file) async {
  try {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  } catch (e) {
    debugPrint('PROFILE IMAGE CONVERT ERROR: $e');
    return null;
  }
}

void showMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade800 : AppColors.deepRed,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// ============================================================
// DASHBOARD
// ============================================================

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int donorCount = 0;
  int bloodGroupCount = 8;

  @override
  void initState() {
    super.initState();
    loadStats();
  }

  Future<void> loadStats() async {
    try {
      final snapshot = await db.collection('donors').get();

      if (mounted) {
        setState(() {
          donorCount = snapshot.docs.length;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.deepRed,
          onRefresh: loadStats,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),

              // TOP HEADER
              Container(
                padding: const EdgeInsets.fromLTRB(20, 25, 20, 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.deepRed,
                      AppColors.red,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(.20),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Image.asset(
  'assets/images/logo.png',
  width: 90,
  height: 90,
  fit: BoxFit.contain,
),
                    const SizedBox(height: 8),
                    Text(
                      'চিকনদন্ডী ব্লাড ডোনারস',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansBengali(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'CHIKANDANDI BLOOD DONORS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.14),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        '“এক ব্যাগ রক্ত, একটি জীবন বাঁচাতে পারে।”',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansBengali(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // PROFILE BUTTON
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (currentDonorId == null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DonorSearchPage(),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfilePage(
                            donorId: currentDonorId!,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.person_outline),
                  label: Text(
                    currentDonorId == null
                        ? 'প্রোফাইল'
                        : 'আমার প্রোফাইল',
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // THREE MAIN OPTIONS

              MainActionCard(
                icon: Icons.person_add_alt_1,
                title: 'রক্তদাতা হিসেবে নিবন্ধন করুন',
                english: 'REGISTER AS A BLOOD DONOR',
                subtitle: 'Become a donor and help save lives',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DonorRegistrationPage(),
                    ),
                  );

                  loadStats();
                },
              ),

              const SizedBox(height: 13),

              MainActionCard(
                icon: Icons.search,
                title: 'রক্তদাতা খুঁজুন',
                english: 'FIND BLOOD DONORS',
                subtitle: 'Search donors by blood group and location',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DonorSearchPage(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 13),

              MainActionCard(
                icon: Icons.emergency,
                title: 'জরুরী রক্তের জন্য অনুরোধ করুন',
                english: 'REQUEST BLOOD URGENTLY',
                subtitle: 'Call our emergency blood support',
                emergency: true,
                onTap: () {
                  callNumber('01883240099');
                },
              ),

              const SizedBox(height: 22),

              // STATS
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      number: '$donorCount',
                      title: 'মোট রক্তদাতা',
                      english: 'TOTAL DONORS',
                      icon: Icons.people,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      number: '$bloodGroupCount',
                      title: 'ব্লাড গ্রুপ',
                      english: 'BLOOD GROUPS',
                      icon: Icons.bloodtype,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              const Divider(),

              const SizedBox(height: 8),

              Center(
                child: Text(
                  'App Created By Kazi Sajid',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MAIN ACTION CARD
// ============================================================

class MainActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String english;
  final String subtitle;
  final VoidCallback onTap;
  final bool emergency;

  const MainActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.english,
    required this.subtitle,
    required this.onTap,
    this.emergency = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: emergency
                ? Colors.red.shade200
                : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.045),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: emergency
                    ? Colors.red.shade50
                    : AppColors.lightRed,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                icon,
                color: AppColors.deepRed,
                size: 30,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansBengali(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    english,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepRed,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: AppColors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 17,
              color: AppColors.deepRed,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// STAT CARD
// ============================================================

class StatCard extends StatelessWidget {
  final String number;
  final String title;
  final String english;
  final IconData icon;

  const StatCard({
    super.key,
    required this.number,
    required this.title,
    required this.english,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 17,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: AppColors.deepRed,
            size: 28,
          ),
          const SizedBox(height: 5),
          Text(
            number,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: AppColors.deepRed,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansBengali(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            english,
            style: GoogleFonts.poppins(
              fontSize: 8,
              color: AppColors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DONOR REGISTRATION
// ============================================================

class DonorRegistrationPage extends StatefulWidget {
  const DonorRegistrationPage({super.key});

  @override
  State<DonorRegistrationPage> createState() =>
      _DonorRegistrationPageState();
}

class _DonorRegistrationPageState
    extends State<DonorRegistrationPage> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final ageController = TextEditingController();
  final weightController = TextEditingController();
  final donationCountController = TextEditingController();
  final phoneController = TextEditingController();

  String? bloodGroup;
  String? district;
  String? upazila;
  String? unionWard;
  String? village;
  String availability = 'উপলব্ধ';

  DateTime? lastDonationDate;
  File? profileImage;
  bool submitting = false;

  // ==========================================================
  // DISTRICTS
  // ==========================================================

  final List<String> districts = [
    'চট্টগ্রাম',
    'ঢাকা',
    'কক্সবাজার',
    'ফেনী',
    'কুমিল্লা',
    'নোয়াখালী',
    'লক্ষ্মীপুর',
    'ব্রাহ্মণবাড়িয়া',
    'চাঁদপুর',
    'খাগড়াছড়ি',
    'রাঙ্গামাটি',
    'বান্দরবান',
    'সিলেট',
    'মৌলভীবাজার',
    'হবিগঞ্জ',
    'সুনামগঞ্জ',
    'রাজশাহী',
    'চাঁপাইনবাবগঞ্জ',
    'নাটোর',
    'নওগাঁ',
    'পাবনা',
    'সিরাজগঞ্জ',
    'বগুড়া',
    'জয়পুরহাট',
    'রংপুর',
    'দিনাজপুর',
    'কুড়িগ্রাম',
    'গাইবান্ধা',
    'লালমনিরহাট',
    'নীলফামারী',
    'পঞ্চগড়',
    'ঠাকুরগাঁও',
    'খুলনা',
    'বাগেরহাট',
    'সাতক্ষীরা',
    'যশোর',
    'ঝিনাইদহ',
    'মাগুরা',
    'নড়াইল',
    'কুষ্টিয়া',
    'চুয়াডাঙ্গা',
    'মেহেরপুর',
    'বরিশাল',
    'ভোলা',
    'পটুয়াখালী',
    'পিরোজপুর',
    'ঝালকাঠি',
    'বরগুনা',
    'ময়মনসিংহ',
    'জামালপুর',
    'নেত্রকোনা',
    'শেরপুর',
    'গাজীপুর',
    'নারায়ণগঞ্জ',
    'নরসিংদী',
    'মানিকগঞ্জ',
    'মুন্সীগঞ্জ',
    'রাজবাড়ী',
    'ফরিদপুর',
    'মাদারীপুর',
    'গোপালগঞ্জ',
    'শরীয়তপুর',
  ];

  // Practical starter location dataset.
  // Firebase phase can move this entire dataset to Firestore.

  final Map<String, List<String>> upazilas = {
    'চট্টগ্রাম': [
      'হাটহাজারী',
      'পটিয়া',
      'রাউজান',
      'রাঙ্গুনিয়া',
      'সীতাকুণ্ড',
      'মীরসরাই',
      'ফটিকছড়ি',
      'লোহাগাড়া',
      'সাতকানিয়া',
      'বাঁশখালী',
      'চন্দনাইশ',
      'আনোয়ারা',
      'কর্ণফুলী',
      'সন্দ্বীপ',
    ],
    'ঢাকা': [
      'সাভার',
      'ধামরাই',
      'কেরানীগঞ্জ',
      'দোহার',
      'নবাবগঞ্জ',
    ],
    'কক্সবাজার': [
      'কক্সবাজার সদর',
      'চকরিয়া',
      'উখিয়া',
      'টেকনাফ',
    ],
    'ফেনী': [
      'ফেনী সদর',
      'ছাগলনাইয়া',
      'দাগনভূঞা',
      'পরশুরাম',
    ],
    'কুমিল্লা': [
      'কুমিল্লা সদর',
      'দাউদকান্দি',
      'চৌদ্দগ্রাম',
      'লাকসাম',
    ],
    'নোয়াখালী': [
      'নোয়াখালী সদর',
      'বেগমগঞ্জ',
      'চাটখিল',
      'সোনাইমুড়ী',
    ],
    'লক্ষ্মীপুর': [
      'লক্ষ্মীপুর সদর',
      'রায়পুর',
      'রামগঞ্জ',
      'রামগতি',
    ],
    'ব্রাহ্মণবাড়িয়া': [
      'ব্রাহ্মণবাড়িয়া সদর',
      'আশুগঞ্জ',
      'কসবা',
      'সরাইল',
    ],
    'চাঁদপুর': [
      'চাঁদপুর সদর',
      'হাইমচর',
      'ফরিদগঞ্জ',
      'মতলব',
    ],
    'খাগড়াছড়ি': [
      'খাগড়াছড়ি সদর',
      'দীঘিনালা',
      'মাটিরাঙ্গা',
      'মানিকছড়ি',
    ],
    'রাঙ্গামাটি': [
      'রাঙ্গামাটি সদর',
      'কাপ্তাই',
      'কাউখালী',
      'বাঘাইছড়ি',
    ],
    'বান্দরবান': [
      'বান্দরবান সদর',
      'লামা',
      'আলীকদম',
      'নাইক্ষ্যংছড়ি',
    ],
    'সিলেট': [
      'সিলেট সদর',
      'বালাগঞ্জ',
      'বিশ্বনাথ',
      'গোলাপগঞ্জ',
    ],
    'মৌলভীবাজার': [
      'মৌলভীবাজার সদর',
      'শ্রীমঙ্গল',
      'কমলগঞ্জ',
      'কুলাউড়া',
    ],
    'হবিগঞ্জ': [
      'হবিগঞ্জ সদর',
      'মাধবপুর',
      'চুনারুঘাট',
      'নবীগঞ্জ',
    ],
    'সুনামগঞ্জ': [
      'সুনামগঞ্জ সদর',
      'ছাতক',
      'জগন্নাথপুর',
      'দিরাই',
    ],
    'রাজশাহী': [
      'রাজশাহী সদর',
      'পবা',
      'চারঘাট',
      'বাঘা',
    ],
    'চাঁপাইনবাবগঞ্জ': [
      'চাঁপাইনবাবগঞ্জ সদর',
      'শিবগঞ্জ',
      'গোমস্তাপুর',
      'নাচোল',
    ],
    'নাটোর': [
      'নাটোর সদর',
      'সিংড়া',
      'বড়াইগ্রাম',
      'লালপুর',
    ],
    'নওগাঁ': [
      'নওগাঁ সদর',
      'মান্দা',
      'আত্রাই',
      'সাপাহার',
    ],
    'পাবনা': [
      'পাবনা সদর',
      'ঈশ্বরদী',
      'সাঁথিয়া',
      'বেড়া',
    ],
    'সিরাজগঞ্জ': [
      'সিরাজগঞ্জ সদর',
      'কাজীপুর',
      'উল্লাপাড়া',
      'শাহজাদপুর',
    ],
    'বগুড়া': [
      'বগুড়া সদর',
      'শেরপুর',
      'শিবগঞ্জ',
      'ধুনট',
    ],
    'জয়পুরহাট': [
      'জয়পুরহাট সদর',
      'পাঁচবিবি',
      'কালাই',
      'ক্ষেতলাল',
    ],
    'রংপুর': [
      'রংপুর সদর',
      'মিঠাপুকুর',
      'পীরগঞ্জ',
      'গঙ্গাচড়া',
    ],
    'দিনাজপুর': [
      'দিনাজপুর সদর',
      'বিরামপুর',
      'পার্বতীপুর',
      'ফুলবাড়ী',
    ],
    'কুড়িগ্রাম': [
      'কুড়িগ্রাম সদর',
      'উলিপুর',
      'রাজারহাট',
      'নাগেশ্বরী',
    ],
    'গাইবান্ধা': [
      'গাইবান্ধা সদর',
      'সাদুল্লাপুর',
      'সুন্দরগঞ্জ',
      'পলাশবাড়ী',
    ],
    'লালমনিরহাট': [
      'লালমনিরহাট সদর',
      'আদিতমারী',
      'কালীগঞ্জ',
      'হাতীবান্ধা',
    ],
    'নীলফামারী': [
      'নীলফামারী সদর',
      'সৈয়দপুর',
      'ডোমার',
      'জলঢাকা',
    ],
    'পঞ্চগড়': [
      'পঞ্চগড় সদর',
      'তেঁতুলিয়া',
      'আটোয়ারী',
      'বোদা',
    ],
    'ঠাকুরগাঁও': [
      'ঠাকুরগাঁও সদর',
      'পীরগঞ্জ',
      'বালিয়াডাঙ্গী',
      'রাণীশংকৈল',
    ],
    'খুলনা': [
      'খুলনা সদর',
      'দাকোপ',
      'ডুমুরিয়া',
      'তেরখাদা',
    ],
    'বাগেরহাট': [
      'বাগেরহাট সদর',
      'ফকিরহাট',
      'মোংলা',
      'মোরেলগঞ্জ',
    ],
    'সাতক্ষীরা': [
      'সাতক্ষীরা সদর',
      'আশাশুনি',
      'কালীগঞ্জ',
      'শ্যামনগর',
    ],
    'যশোর': [
      'যশোর সদর',
      'ঝিকরগাছা',
      'অভয়নগর',
      'মনিরামপুর',
    ],
    'ঝিনাইদহ': [
      'ঝিনাইদহ সদর',
      'শৈলকুপা',
      'কালীগঞ্জ',
      'কোটচাঁদপুর',
    ],
    'মাগুরা': [
      'মাগুরা সদর',
      'শ্রীপুর',
      'শালিখা',
      'মোহাম্মদপুর',
    ],
    'নড়াইল': [
      'নড়াইল সদর',
      'লোহাগড়া',
      'কালিয়া',
    ],
    'কুষ্টিয়া': [
      'কুষ্টিয়া সদর',
      'কুমারখালী',
      'মিরপুর',
      'দৌলতপুর',
    ],
    'চুয়াডাঙ্গা': [
      'চুয়াডাঙ্গা সদর',
      'আলমডাঙ্গা',
      'দামুড়হুদা',
      'জীবননগর',
    ],
    'মেহেরপুর': [
      'মেহেরপুর সদর',
      'গাংনী',
      'মুজিবনগর',
    ],
    'বরিশাল': [
      'বরিশাল সদর',
      'বাকেরগঞ্জ',
      'উজিরপুর',
      'বানারীপাড়া',
    ],
    'ভোলা': [
      'ভোলা সদর',
      'বোরহানউদ্দিন',
      'চরফ্যাশন',
      'দৌলতখান',
    ],
    'পটুয়াখালী': [
      'পটুয়াখালী সদর',
      'বাউফল',
      'কলাপাড়া',
      'দশমিনা',
    ],
    'পিরোজপুর': [
      'পিরোজপুর সদর',
      'ভান্ডারিয়া',
      'মঠবাড়িয়া',
      'নাজিরপুর',
    ],
    'ঝালকাঠি': [
      'ঝালকাঠি সদর',
      'নলছিটি',
      'কাঁঠালিয়া',
      'রাজাপুর',
    ],
    'বরগুনা': [
      'বরগুনা সদর',
      'আমতলী',
      'বেতাগী',
      'পাথরঘাটা',
    ],
    'ময়মনসিংহ': [
      'ময়মনসিংহ সদর',
      'ত্রিশাল',
      'ভালুকা',
      'মুক্তাগাছা',
    ],
    'জামালপুর': [
      'জামালপুর সদর',
      'মেলান্দহ',
      'ইসলামপুর',
      'সরিষাবাড়ী',
    ],
    'নেত্রকোনা': [
      'নেত্রকোনা সদর',
      'বারহাট্টা',
      'দুর্গাপুর',
      'কলমাকান্দা',
    ],
    'শেরপুর': [
      'শেরপুর সদর',
      'নালিতাবাড়ী',
      'শ্রীবরদী',
      'নকলা',
    ],
    'গাজীপুর': [
      'গাজীপুর সদর',
      'কালিয়াকৈর',
      'কালীগঞ্জ',
      'কাপাসিয়া',
    ],
    'নারায়ণগঞ্জ': [
      'নারায়ণগঞ্জ সদর',
      'আড়াইহাজার',
      'রূপগঞ্জ',
      'সোনারগাঁও',
    ],
    'নরসিংদী': [
      'নরসিংদী সদর',
      'রায়পুরা',
      'শিবপুর',
      'মনোহরদী',
    ],
    'মানিকগঞ্জ': [
      'মানিকগঞ্জ সদর',
      'সাটুরিয়া',
      'সিংগাইর',
      'শিবালয়',
    ],
    'মুন্সীগঞ্জ': [
      'মুন্সীগঞ্জ সদর',
      'শ্রীনগর',
      'সিরাজদিখান',
      'টঙ্গীবাড়ী',
    ],
    'রাজবাড়ী': [
      'রাজবাড়ী সদর',
      'পাংশা',
      'বালিয়াকান্দি',
      'গোয়ালন্দ',
    ],
    'ফরিদপুর': [
      'ফরিদপুর সদর',
      'ভাঙ্গা',
      'বোয়ালমারী',
      'নগরকান্দা',
    ],
    'মাদারীপুর': [
      'মাদারীপুর সদর',
      'কালকিনি',
      'রাজৈর',
      'শিবচর',
    ],
    'গোপালগঞ্জ': [
      'গোপালগঞ্জ সদর',
      'কাশিয়ানী',
      'কোটালীপাড়া',
      'টুঙ্গিপাড়া',
    ],
    'শরীয়তপুর': [
      'শরীয়তপুর সদর',
      'জাজিরা',
      'নড়িয়া',
      'ভেদরগঞ্জ',
    ],
  };

  // Chattogram unions/wards.
  // Other districts use location choices generated below.
  final Map<String, List<String>> unions = {
    'হাটহাজারী': [
      'ফতেপুর',
      'চিকনদন্ডী',
      'দক্ষিণ মাদার্শা',
      'উত্তর মাদার্শা',
      'মির্জাপুর',
      'শিকারপুর',
      'বুড়িশ্চর',
      'ফরহাদাবাদ',
      'লাঙ্গলমোড়া',
      'গড়দুয়ারা',
      'মেখল',
      'গুমানমর্দ্দন',
      'ছিপাতলী',
      'ধলই',
    ],
    'পটিয়া': [
      'কুসুমপুরা',
      'জিরি',
      'কেলিশহর',
      'হাবিলাসদ্বীপ',
      'শোভনদণ্ডী',
    ],
    'রাউজান': [
      'বাগোয়ান',
      'বিনাজুরী',
      'হলদিয়া',
      'কদলপুর',
      'গহিরা',
    ],
    'রাঙ্গুনিয়া': [
      'রাজানগর',
      'পোমরা',
      'স্বনির্ভর রাঙ্গুনিয়া',
      'চন্দ্রঘোনা',
      'শিলক',
    ],
    'সীতাকুণ্ড': [
      'বাঁশবাড়ীয়া',
      'বারৈয়াঢালা',
      'ভাটিয়ারী',
      'কুমিরা',
      'সোনাইছড়ি',
    ],
    'মীরসরাই': [
      'মীরসরাই',
      'বারইয়ারহাট',
      'দুর্গাপুর',
      'খৈয়াছড়া',
      'মায়ানী',
    ],
    'ফটিকছড়ি': [
      'বাগানবাজার',
      'ভূজপুর',
      'নারায়ণহাট',
      'সুন্দরপুর',
      'বক্তপুর',
    ],
    'লোহাগাড়া': [
      'লোহাগাড়া',
      'আমিরাবাদ',
      'চুনতি',
      'পদুয়া',
      'পুটিবিলা',
    ],
    'সাতকানিয়া': [
      'কেঁওচিয়া',
      'খাগরিয়া',
      'কাঞ্চনা',
      'মাদার্শা',
      'সাতকানিয়া',
    ],
    'বাঁশখালী': [
      'বাহারছড়া',
      'পুকুরিয়া',
      'কালীপুর',
      'কাথরিয়া',
      'চাম্বল',
    ],
    'চন্দনাইশ': [
      'বরকল',
      'বরমা',
      'দোহাজারী',
      'হাশিমপুর',
      'জোয়ারা',
    ],
    'আনোয়ারা': [
      'বারখাইন',
      'বটতলী',
      'বরুমচড়া',
      'চাতরী',
      'পরৈকোড়া',
    ],
    'কর্ণফুলী': [
      'বড়উঠান',
      'চরলক্ষ্যা',
      'জুলধা',
      'শিকলবাহা',
      'চরপাথরঘাটা',
    ],
    'সন্দ্বীপ': [
      'সন্দ্বীপ',
      'মাইটভাঙ্গা',
      'হারামিয়া',
      'মুছাপুর',
      'আমিরাবাদ',
    ],
  };

  List<String> getCurrentUpazilas() {
    if (district == null) return [];
    return upazilas[district] ?? [
      '$district উপজেলা - ১',
      '$district উপজেলা - ২',
    ];
  }

  List<String> getCurrentUnions() {
    if (upazila == null) return [];

    return unions[upazila] ?? [
      '$upazila ইউনিয়ন/ওয়ার্ড - ১',
      '$upazila ইউনিয়ন/ওয়ার্ড - ২',
    ];
  }

  Future<void> selectImage() async {
    final XFile? picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked != null) {
      setState(() {
        profileImage = File(picked.path);
      });
    }
  }

  Future<void> chooseLastDonationDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
      helpText: 'সর্বশেষ রক্তদানের তারিখ নির্বাচন করুন',
    );

    if (date != null) {
      setState(() {
        lastDonationDate = date;
      });
    }
  }

  Future<void> submitRegistration() async {
    if (!formKey.currentState!.validate()) return;

    if (bloodGroup == null ||
        district == null ||
        upazila == null ||
        unionWard == null) {
      showMessage(
        context,
        'রক্তের গ্রুপ ও সম্পূর্ণ ঠিকানা নির্বাচন করুন।',
        error: true,
      );
      return;
    }

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final normalizedName = normalizeName(name);
    final normalizedPhone = normalizePhone(phone);

    setState(() {
      submitting = true;
    });

    try {
      final existing = await db.collection('donors').get();
      final duplicate = existing.docs.any((doc) {
        final data = doc.data();
        return normalizeName((data['name'] ?? '').toString()) ==
                normalizedName &&
            normalizePhone((data['phone'] ?? '').toString()) ==
                normalizedPhone &&
            (data['bloodGroup'] ?? '').toString() == bloodGroup;
      });

      if (duplicate) {
        if (!mounted) return;
        setState(() {
          submitting = false;
        });
        showMessage(
          context,
          'এই নাম, মোবাইল নাম্বার ও ব্লাড গ্রুপ দিয়ে আগে থেকেই নিবন্ধন করা আছে।',
          error: true,
        );
        return;
      }

      String? imageUrl;

      if (profileImage != null) {
  imageUrl = await profileImageToBase64(profileImage!);

        if (imageUrl == null) {
          if (!mounted) return;
          setState(() {
            submitting = false;
          });
          showMessage(
            context,
            'ছবি আপলোড করা যায়নি। আবার ছবি নির্বাচন করে চেষ্টা করুন।',
            error: true,
          );
          return;
        }
      }

      final doc = await db.collection('donors').add({
        'name': name,
        'bloodGroup': bloodGroup,
        'age': int.tryParse(ageController.text.trim()) ?? 0,
        'weight': double.tryParse(weightController.text.trim()) ?? 0,
        'lastDonationDate': lastDonationDate != null
            ? Timestamp.fromDate(lastDonationDate!)
            : null,
        'totalDonations':
            int.tryParse(donationCountController.text.trim()) ?? 0,
        'phone': phone,
        'district': district,
        'upazila': upazila,
        'unionWard': unionWard,
        'village': villageController.text.trim(),
        'availability': lastDonationDate != null
            ? getEffectiveAvailability({
                'lastDonationDate': Timestamp.fromDate(lastDonationDate!),
                'availability': availability,
              })
            : availability,
        'profileImage': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      currentDonorId = doc.id;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('currentDonorId', doc.id);

      if (!mounted) return;

      setState(() {
        submitting = false;
      });

      showMessage(
        context,
        'অভিনন্দন! আপনার রক্তদাতা নিবন্ধন সফল হয়েছে।',
      );

      await Future.delayed(const Duration(milliseconds: 700));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(
              donorId: doc.id,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('REGISTRATION ERROR: $e');

      if (!mounted) return;

      setState(() {
        submitting = false;
      });

      showMessage(
        context,
        'নিবন্ধন করা যায়নি। Firebase connection পরীক্ষা করুন।',
        error: true,
      );
    }
  }

  final villageController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    weightController.dispose();
    donationCountController.dispose();
    phoneController.dispose();
    villageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('রক্তদাতা নিবন্ধন'),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(17),
          children: [
            Text(
              'রক্তদাতা হিসেবে নিবন্ধন করুন',
              style: GoogleFonts.notoSansBengali(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.deepRed,
              ),
            ),
            Text(
              'REGISTER AS A BLOOD DONOR',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.grey,
              ),
            ),

            const SizedBox(height: 18),

            // PROFILE PHOTO
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: AppColors.lightRed,
                    backgroundImage: profileImage != null
                        ? FileImage(profileImage!)
                        : null,
                    child: profileImage == null
                        ? const Icon(
                            Icons.person,
                            color: AppColors.deepRed,
                            size: 55,
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: selectImage,
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: const BoxDecoration(
                          color: AppColors.deepRed,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 5),

            Center(
              child: Text(
                'ছবি (ঐচ্ছিক)',
                style: GoogleFonts.notoSansBengali(
                  color: AppColors.grey,
                  fontSize: 12,
                ),
              ),
            ),

            const SizedBox(height: 20),

            AppTextField(
              controller: nameController,
              label: 'নাম',
              english: 'FULL NAME',
              icon: Icons.person_outline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'নাম লিখুন';
                }
                return null;
              },
            ),

            const SizedBox(height: 13),

            AppDropdown(
              label: 'রক্তের গ্রুপ',
              english: 'BLOOD GROUP',
              value: bloodGroup,
              items: const [
                'A+',
                'A-',
                'B+',
                'B-',
                'AB+',
                'AB-',
                'O+',
                'O-',
              ],
              onChanged: (value) {
                setState(() {
                  bloodGroup = value;
                });
              },
            ),

            const SizedBox(height: 13),

            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: ageController,
                    label: 'বয়স',
                    english: 'AGE',
                    icon: Icons.cake_outlined,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'বয়স দিন';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: weightController,
                    label: 'ওজন (কেজি)',
                    english: 'WEIGHT',
                    icon: Icons.monitor_weight_outlined,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'ওজন দিন';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 13),

            DatePickerField(
              title: 'সর্বশেষ রক্তদানের তারিখ',
              english: 'LAST BLOOD DONATION',
              date: lastDonationDate,
              onTap: chooseLastDonationDate,
            ),

            const SizedBox(height: 13),

            AppTextField(
              controller: donationCountController,
              label: 'মোট কয়বার রক্তদান করেছেন',
              english: 'TOTAL DONATIONS',
              icon: Icons.volunteer_activism_outlined,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'মোট রক্তদানের সংখ্যা লিখুন';
                }
                return null;
              },
            ),

            const SizedBox(height: 13),

            AppTextField(
              controller: phoneController,
              label: 'মোবাইল নাম্বার',
              english: 'MOBILE NUMBER',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'মোবাইল নাম্বার লিখুন';
                }

                if (value.trim().length < 11) {
                  return 'সঠিক মোবাইল নাম্বার দিন';
                }

                return null;
              },
            ),

            const SizedBox(height: 20),

            SectionTitle(
              title: 'ঠিকানা',
              english: 'ADDRESS',
            ),

            const SizedBox(height: 10),

            AppDropdown(
              label: 'জেলা',
              english: 'DISTRICT',
              value: district,
              items: districts,
              onChanged: (value) {
                setState(() {
                  district = value;
                  upazila = null;
                  unionWard = null;
                });
              },
            ),

            const SizedBox(height: 13),

            AppDropdown(
              label: 'উপজেলা / সিটি কর্পোরেশন',
              english: 'UPAZILA / CITY CORPORATION',
              value: upazila,
              items: getCurrentUpazilas(),
              enabled: district != null,
              onChanged: (value) {
                setState(() {
                  upazila = value;
                  unionWard = null;
                });
              },
            ),

            const SizedBox(height: 13),

            AppDropdown(
              label: 'ইউনিয়ন / ওয়ার্ড',
              english: 'UNION / WARD',
              value: unionWard,
              items: getCurrentUnions(),
              enabled: upazila != null,
              onChanged: (value) {
                setState(() {
                  unionWard = value;
                });
              },
            ),

            const SizedBox(height: 13),

            AppTextField(
              controller: villageController,
              label: 'গ্রাম',
              english: 'VILLAGE - OPTIONAL',
              icon: Icons.home_outlined,
            ),

            const SizedBox(height: 22),

            SectionTitle(
              title:
                  'আপনি কি বর্তমানে রক্তদান করতে শারীরিক ও মানসিকভাবে প্রস্তুত আছেন?',
              english: 'CURRENT DONATION AVAILABILITY',
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: AvailabilityButton(
                    title: 'উপলব্ধ',
                    english: 'AVAILABLE',
                    selected: availability == 'উপলব্ধ',
                    icon: Icons.check_circle,
                    onTap: () {
                      setState(() {
                        availability = 'উপলব্ধ';
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AvailabilityButton(
                    title: 'অনুপলব্ধ',
                    english: 'UNAVAILABLE',
                    selected: availability == 'অনুপলব্ধ',
                    icon: Icons.cancel,
                    onTap: () {
                      setState(() {
                        availability = 'অনুপলব্ধ';
                      });
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            SizedBox(
              height: 55,
              child: ElevatedButton.icon(
                onPressed: submitting ? null : submitRegistration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  submitting ? 'নিবন্ধন হচ্ছে...' : 'সাবমিট করুন',
                  style: GoogleFonts.notoSansBengali(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SEARCH DONORS
// ============================================================

class DonorSearchPage extends StatefulWidget {
  const DonorSearchPage({super.key});

  @override
  State<DonorSearchPage> createState() => _DonorSearchPageState();
}

class _DonorSearchPageState extends State<DonorSearchPage> {
  String? selectedBloodGroup;
  String? selectedDistrict;
  String? selectedUpazila;

  final List<String> districts = const [
    'চট্টগ্রাম',
    'ঢাকা',
    'কক্সবাজার',
    'ফেনী',
    'কুমিল্লা',
    'নোয়াখালী',
    'লক্ষ্মীপুর',
    'সিলেট',
    'রাজশাহী',
    'রংপুর',
    'খুলনা',
    'বরিশাল',
    'ময়মনসিংহ',
    'গাজীপুর',
    'নারায়ণগঞ্জ',
  ];

  final Map<String, List<String>> searchUpazilas = {
    'চট্টগ্রাম': [
      'হাটহাজারী',
      'পটিয়া',
      'রাউজান',
      'রাঙ্গুনিয়া',
      'সীতাকুণ্ড',
      'মীরসরাই',
    ],
    'ঢাকা': [
      'সাভার',
      'ধামরাই',
      'কেরানীগঞ্জ',
      'দোহার',
      'নবাবগঞ্জ',
    ],
    'কক্সবাজার': [
      'কক্সবাজার সদর',
      'চকরিয়া',
      'উখিয়া',
      'টেকনাফ',
    ],
    'ফেনী': [
      'ফেনী সদর',
      'ছাগলনাইয়া',
      'দাগনভূঞা',
    ],
    'কুমিল্লা': [
      'কুমিল্লা সদর',
      'দাউদকান্দি',
      'চৌদ্দগ্রাম',
    ],
    'নোয়াখালী': [
      'নোয়াখালী সদর',
      'বেগমগঞ্জ',
      'চাটখিল',
    ],
    'সিলেট': [
      'সিলেট সদর',
      'বালাগঞ্জ',
      'বিশ্বনাথ',
    ],
    'রাজশাহী': [
      'রাজশাহী সদর',
      'পবা',
      'চারঘাট',
    ],
    'রংপুর': [
      'রংপুর সদর',
      'মিঠাপুকুর',
      'পীরগঞ্জ',
    ],
    'খুলনা': [
      'খুলনা সদর',
      'দাকোপ',
      'ডুমুরিয়া',
    ],
    'বরিশাল': [
      'বরিশাল সদর',
      'বাকেরগঞ্জ',
      'উজিরপুর',
    ],
    'ময়মনসিংহ': [
      'ময়মনসিংহ সদর',
      'ত্রিশাল',
      'ভালুকা',
    ],
    'গাজীপুর': [
      'গাজীপুর সদর',
      'কালিয়াকৈর',
      'কালীগঞ্জ',
    ],
    'নারায়ণগঞ্জ': [
      'নারায়ণগঞ্জ সদর',
      'আড়াইহাজার',
      'রূপগঞ্জ',
    ],
  };

  List<QueryDocumentSnapshot<Map<String, dynamic>>> donors = [];

  bool loading = false;

  Future<void> searchDonors() async {
    setState(() {
      loading = true;
    });

    try {
      Query<Map<String, dynamic>> query = db.collection('donors');

      if (selectedBloodGroup != null) {
        query = query.where(
          'bloodGroup',
          isEqualTo: selectedBloodGroup,
        );
      }

      if (selectedDistrict != null) {
        query = query.where(
          'district',
          isEqualTo: selectedDistrict,
        );
      }

      if (selectedUpazila != null) {
        query = query.where(
          'upazila',
          isEqualTo: selectedUpazila,
        );
      }

      final result = await query.get();

      for (final doc in result.docs) {
        final data = doc.data();
        await refreshDonorAvailability(doc.id, data);
      }

      if (mounted) {
        setState(() {
          donors = result.docs;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
        });

        showMessage(
          context,
          'ডোনার খুঁজে পাওয়া যায়নি।',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('রক্তদাতা খুঁজুন'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionTitle(
                  title: 'রক্তের গ্রুপ সিলেক্ট করুন',
                  english: 'SELECT BLOOD GROUP',
                ),

                const SizedBox(height: 10),

                AppDropdown(
                  label: 'রক্তের গ্রুপ',
                  english: 'BLOOD GROUP',
                  value: selectedBloodGroup,
                  items: const [
                    'A+',
                    'A-',
                    'B+',
                    'B-',
                    'AB+',
                    'AB-',
                    'O+',
                    'O-',
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedBloodGroup = value;
                    });
                    searchDonors();
                  },
                ),

                const SizedBox(height: 18),

                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      selectedBloodGroup = null;
                      selectedDistrict = null;
                      selectedUpazila = null;
                    });
                    searchDonors();
                  },
                  icon: const Icon(Icons.people_outline),
                  label: Text(
                    'সকল রক্তদাতা দেখুন • VIEW ALL DONORS',
                    style: GoogleFonts.notoSansBengali(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      selectedBloodGroup = null;
                      selectedDistrict = null;
                      selectedUpazila = null;
                    });
                    searchDonors();
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: Text(
                    'সকল জেলার রক্তদাতা দেখুন • ALL DISTRICTS',
                    style: GoogleFonts.notoSansBengali(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                SectionTitle(
                  title: 'জেলা ও উপজেলা দিয়ে ফিল্টার করুন',
                  english: 'FILTER BY LOCATION',
                ),

                const SizedBox(height: 10),

                AppDropdown(
                  label: 'জেলা',
                  english: 'DISTRICT',
                  value: selectedDistrict,
                  items: districts,
                  onChanged: (value) {
                    setState(() {
                      selectedDistrict = value;
                      selectedUpazila = null;
                    });
                    searchDonors();
                  },
                ),

                const SizedBox(height: 10),

                AppDropdown(
                  label: 'উপজেলা / সিটি কর্পোরেশন',
                  english: 'UPAZILA / CITY',
                  value: selectedUpazila,
                  items: selectedDistrict == null
                      ? []
                      : (searchUpazilas[selectedDistrict] ??
                          [
                            '$selectedDistrict উপজেলা - ১',
                            '$selectedDistrict উপজেলা - ২',
                          ]),
                  enabled: selectedDistrict != null,
                  onChanged: (value) {
                    setState(() {
                      selectedUpazila = value;
                    });
                    searchDonors();
                  },
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'রক্তদাতাদের তালিকা',
                        style: GoogleFonts.notoSansBengali(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.deepRed,
                        ),
                      ),
                    ),
                    Text(
                      '${donors.length} জন',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.deepRed,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepRed,
                      ),
                    ),
                  ),

                if (!loading && donors.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.search_off,
                          size: 45,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'কোনো রক্তদাতা পাওয়া যায়নি',
                          style: GoogleFonts.notoSansBengali(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                ...donors.map(
                  (doc) => DonorCard(
                    donorId: doc.id,
                    data: doc.data(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DONOR CARD
// ============================================================

class DonorCard extends StatelessWidget {
  final String donorId;
  final Map<String, dynamic> data;

  const DonorCard({
    super.key,
    required this.donorId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final image = data['profileImage'];
    final name = data['name'] ?? 'Unknown';
    final blood = data['bloodGroup'] ?? '-';
    final phone = data['phone'] ?? '';
    final availability = getEffectiveAvailability(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.045),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppColors.lightRed,
            backgroundImage:
                image != null && image.toString().isNotEmpty
                    ? MemoryImage(
    base64Decode(image.toString()),
  )
: null,
            child: (image == null || image.toString().isEmpty)
                ? const Icon(
                    Icons.person,
                    color: AppColors.deepRed,
                    size: 32,
                  )
                : null,
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansBengali(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 3),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.deepRed,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        blood,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${data['unionWard'] ?? ''}, '
                        '${data['upazila'] ?? ''}, '
                        '${data['district'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansBengali(
                          fontSize: 10,
                          color: AppColors.grey,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 5),

                Row(
                  children: [
                    Icon(
                      availability == 'উপলব্ধ'
                          ? Icons.check_circle
                          : Icons.cancel,
                      size: 13,
                      color: availability == 'উপলব্ধ'
                          ? AppColors.green
                          : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      availability,
                      style: GoogleFonts.notoSansBengali(
                        fontSize: 10,
                        color: data['availability'] == 'উপলব্ধ'
                            ? AppColors.green
                            : AppColors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          SizedBox(
            width: 60,
            child: ElevatedButton(
              onPressed: phone.toString().isEmpty
                  ? null
                  : () => callNumber(phone.toString()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 9,
                  horizontal: 5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Icon(
                Icons.call,
                size: 21,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PROFILE
// ============================================================

class ProfilePage extends StatefulWidget {
  final String donorId;

  const ProfilePage({
    super.key,
    required this.donorId,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? donorData;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    try {
      final doc =
          await db.collection('donors').doc(widget.donorId).get();

      final data = doc.data();
      if (data != null) {
        await refreshDonorAvailability(widget.donorId, data);
        data['availability'] = getEffectiveAvailability(data);
      }

      if (mounted) {
        setState(() {
          donorData = doc.data();
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.deepRed,
          ),
        ),
      );
    }

    if (donorData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('প্রোফাইল')),
        body: const Center(
          child: Text('প্রোফাইল পাওয়া যায়নি'),
        ),
      );
    }

    final data = donorData!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('আমার প্রোফাইল'),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfilePage(
                    donorId: widget.donorId,
                    data: data,
                  ),
                ),
              );
              loadProfile();
            },
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 58,
              backgroundColor: AppColors.lightRed,
              backgroundImage: data['profileImage'] != null &&
        data['profileImage'].toString().isNotEmpty
    ? MemoryImage(
        base64Decode(data['profileImage'].toString()),
      )
    : null,
child: data['profileImage'] == null ||
        data['profileImage'].toString().isEmpty
    ? const Icon(
        Icons.person,
        size: 58,
        color: AppColors.deepRed,
      )
    : null,
            ),
          ),

          const SizedBox(height: 13),

          Center(
            child: Text(
              data['name'] ?? '',
              style: GoogleFonts.notoSansBengali(
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),

          const SizedBox(height: 4),

          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.deepRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                data['bloodGroup'] ?? '-',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          ProfileInfoTile(
            icon: Icons.phone,
            title: 'মোবাইল',
            value: data['phone'] ?? '-',
          ),

          ProfileInfoTile(
            icon: Icons.cake,
            title: 'বয়স',
            value: '${data['age'] ?? '-'} বছর',
          ),

          ProfileInfoTile(
            icon: Icons.monitor_weight,
            title: 'ওজন',
            value: '${data['weight'] ?? '-'} কেজি',
          ),

          ProfileInfoTile(
            icon: Icons.location_on,
            title: 'ঠিকানা',
            value:
                '${data['unionWard'] ?? ''}, '
                '${data['upazila'] ?? ''}, '
                '${data['district'] ?? ''}',
          ),

          ProfileInfoTile(
            icon: Icons.volunteer_activism,
            title: 'মোট রক্তদান',
            value: '${data['totalDonations'] ?? 0} বার',
          ),

          ProfileInfoTile(
            icon: Icons.access_time,
            title: 'বর্তমান অবস্থা',
            value: getEffectiveAvailability(data),
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DonationTodayPage(
                      donorId: widget.donorId,
                      donorName: data['name'] ?? '',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.bloodtype),
              label: Text(
                'আমি আজকে রক্তদান করেছি',
                style: GoogleFonts.notoSansBengali(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            'I DONATED BLOOD TODAY',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EDIT PROFILE
// ============================================================

class EditProfilePage extends StatefulWidget {
  final String donorId;
  final Map<String, dynamic> data;

  const EditProfilePage({
    super.key,
    required this.donorId,
    required this.data,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController nameController;
  late TextEditingController ageController;
  late TextEditingController weightController;
  late TextEditingController donationsController;
  late TextEditingController phoneController;
  late TextEditingController villageController;

  String? bloodGroup;
  String? district;
  String? upazila;
  String? unionWard;
  String availability = 'উপলব্ধ';

  bool saving = false;
  File? profileImage;

  final List<String> bloodGroups = const [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  final List<String> districts = const [
    'চট্টগ্রাম',
    'ঢাকা',
    'কক্সবাজার',
    'ফেনী',
    'কুমিল্লা',
    'নোয়াখালী',
    'লক্ষ্মীপুর',
    'সিলেট',
    'রাজশাহী',
    'রংপুর',
    'খুলনা',
    'বরিশাল',
    'ময়মনসিংহ',
    'গাজীপুর',
    'নারায়ণগঞ্জ',
  ];

  @override
  void initState() {
    super.initState();

    final d = widget.data;

    nameController = TextEditingController(text: d['name'] ?? '');
    ageController = TextEditingController(text: '${d['age'] ?? ''}');
    weightController = TextEditingController(text: '${d['weight'] ?? ''}');
    donationsController =
        TextEditingController(text: '${d['totalDonations'] ?? 0}');
    phoneController = TextEditingController(text: d['phone'] ?? '');
    villageController = TextEditingController(text: d['village'] ?? '');

    bloodGroup = d['bloodGroup'];
    district = d['district'];
    upazila = d['upazila'];
    unionWard = d['unionWard'];
    availability = getEffectiveAvailability(d);
  }

  List<String> getUpazilas() {
    if (district == null) return [];

    const map = {
      'চট্টগ্রাম': [
        'হাটহাজারী',
        'পটিয়া',
        'রাউজান',
        'রাঙ্গুনিয়া',
        'সীতাকুণ্ড',
        'মীরসরাই',
      ],
      'ঢাকা': [
        'সাভার',
        'ধামরাই',
        'কেরানীগঞ্জ',
        'দোহার',
        'নবাবগঞ্জ',
      ],
      'কক্সবাজার': [
        'কক্সবাজার সদর',
        'চকরিয়া',
        'উখিয়া',
        'টেকনাফ',
      ],
    };

    return map[district] ?? [
      '$district উপজেলা - ১',
      '$district উপজেলা - ২',
    ];
  }

  List<String> getUnions() {
    if (upazila == null) return [];

    const map = {
      'হাটহাজারী': [
        'ফতেপুর',
        'মেখল',
        'গুমানমর্দ্দন',
        'ছিপাতলী',
      ],
      'পটিয়া': [
        'কুসুমপুরা',
        'জিরি',
        'কেলিশহর',
        'হাবিলাসদ্বীপ',
      ],
      'রাউজান': [
        'বাগোয়ান',
        'বিনাজুরী',
        'হলদিয়া',
        'কদলপুর',
      ],
    };

    return map[upazila] ?? [
      '$upazila ইউনিয়ন/ওয়ার্ড - ১',
      '$upazila ইউনিয়ন/ওয়ার্ড - ২',
    ];
  }

  Future<void> selectImage() async {
    final XFile? picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (picked != null) {
      setState(() {
        profileImage = File(picked.path);
      });
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
    });

    try {
      final updateData = <String, dynamic>{
        'name': nameController.text.trim(),
        'bloodGroup': bloodGroup,
        'age': int.tryParse(ageController.text) ?? 0,
        'weight': double.tryParse(weightController.text) ?? 0,
        'totalDonations':
            int.tryParse(donationsController.text) ?? 0,
        'phone': phoneController.text.trim(),
        'district': district,
        'upazila': upazila,
        'unionWard': unionWard,
        'village': villageController.text.trim(),
        'availability': availability,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (profileImage != null) {
        final imageBase64 = await profileImageToBase64(profileImage!);

if (imageBase64 == null) {
  if (!mounted) return;
  setState(() {
    saving = false;
  });
  showMessage(
    context,
    'ছবি প্রস্তুত করা যায়নি। আবার চেষ্টা করুন।',
    error: true,
  );
  return;
}

updateData['profileImage'] = imageBase64;
      }

      await db.collection('donors').doc(widget.donorId).update(updateData);

      if (!mounted) return;

      setState(() {
        saving = false;
      });

      showMessage(context, 'প্রোফাইল সফলভাবে আপডেট হয়েছে।');
      Navigator.pop(context);
    } catch (e) {
      debugPrint('PROFILE UPDATE ERROR: $e');

      if (!mounted) return;

      setState(() {
        saving = false;
      });

      showMessage(
        context,
        'আপডেট করা যায়নি।',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingImage = widget.data['profileImage'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('প্রোফাইল সম্পাদনা'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: selectImage,
              child: CircleAvatar(
                radius: 58,
                backgroundColor: AppColors.lightRed,
                backgroundImage: profileImage != null
                    ? FileImage(profileImage!)
                    : (existingImage != null &&
                            existingImage.toString().isNotEmpty
                        ? NetworkImage(existingImage.toString())
                        : null),
                child: profileImage == null &&
                        (existingImage == null ||
                            existingImage.toString().isEmpty)
                    ? const Icon(
                        Icons.person,
                        size: 58,
                        color: AppColors.deepRed,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: selectImage,
              icon: const Icon(Icons.photo),
              label: Text(
                'প্রোফাইল ছবি পরিবর্তন করুন',
                style: GoogleFonts.notoSansBengali(),
              ),
            ),
          ),
          const SizedBox(height: 15),
          SectionTitle(
            title: 'ব্যক্তিগত তথ্য',
            english: 'PERSONAL INFORMATION',
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: nameController,
            label: 'নাম',
            english: 'NAME',
            icon: Icons.person,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: ageController,
            label: 'বয়স',
            english: 'AGE',
            icon: Icons.cake,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: weightController,
            label: 'ওজন',
            english: 'WEIGHT',
            icon: Icons.monitor_weight,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: donationsController,
            label: 'মোট রক্তদান',
            english: 'TOTAL DONATIONS',
            icon: Icons.volunteer_activism,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: phoneController,
            label: 'মোবাইল নম্বর',
            english: 'PHONE NUMBER',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          AppDropdown(
            label: 'রক্তের গ্রুপ',
            english: 'BLOOD GROUP',
            value: bloodGroup,
            items: bloodGroups,
            onChanged: (value) {
              setState(() {
                bloodGroup = value;
              });
            },
          ),
          const SizedBox(height: 12),
          SectionTitle(
            title: 'ঠিকানা',
            english: 'ADDRESS',
          ),
          const SizedBox(height: 12),
          AppDropdown(
            label: 'জেলা',
            english: 'DISTRICT',
            value: district,
            items: districts,
            onChanged: (value) {
              setState(() {
                district = value;
                upazila = null;
                unionWard = null;
              });
            },
          ),
          const SizedBox(height: 12),
          AppDropdown(
            label: 'উপজেলা',
            english: 'UPAZILA',
            value: upazila,
            items: getUpazilas(),
            enabled: district != null,
            onChanged: (value) {
              setState(() {
                upazila = value;
                unionWard = null;
              });
            },
          ),
          const SizedBox(height: 12),
          AppDropdown(
            label: 'ইউনিয়ন / ওয়ার্ড',
            english: 'UNION / WARD',
            value: unionWard,
            items: getUnions(),
            enabled: upazila != null,
            onChanged: (value) {
              setState(() {
                unionWard = value;
              });
            },
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: villageController,
            label: 'গ্রাম / মহল্লা',
            english: 'VILLAGE / AREA',
            icon: Icons.home,
          ),
          const SizedBox(height: 18),
          SectionTitle(
            title: 'রক্তদানের বর্তমান অবস্থা',
            english: 'AVAILABILITY',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AvailabilityButton(
                  title: 'উপলব্ধ',
                  english: 'AVAILABLE',
                  selected: availability == 'উপলব্ধ',
                  icon: Icons.check_circle,
                  onTap: () {
                    setState(() {
                      availability = 'উপলব্ধ';
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AvailabilityButton(
                  title: 'অনুপলব্ধ',
                  english: 'UNAVAILABLE',
                  selected: availability == 'অনুপলব্ধ',
                  icon: Icons.cancel,
                  onTap: () {
                    setState(() {
                      availability = 'অনুপলব্ধ';
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: saving ? null : save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepRed,
                foregroundColor: Colors.white,
              ),
              child: Text(
                saving ? 'সংরক্ষণ হচ্ছে...' : 'পরিবর্তন সংরক্ষণ করুন',
                style: GoogleFonts.notoSansBengali(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    weightController.dispose();
    donationsController.dispose();
    phoneController.dispose();
    villageController.dispose();
    super.dispose();
  }
}

// ============================================================
// TODAY DONATION
// ============================================================

class DonationTodayPage extends StatefulWidget {
  final String donorId;
  final String donorName;

  const DonationTodayPage({
    super.key,
    required this.donorId,
    required this.donorName,
  });

  @override
  State<DonationTodayPage> createState() =>
      _DonationTodayPageState();
}

class _DonationTodayPageState extends State<DonationTodayPage> {
  DateTime? donationDate;

  final patientController = TextEditingController();
  final hospitalController = TextEditingController();

  String donatedThroughApp = 'হ্যাঁ';
  File? donationPhoto;
  bool permissionForFacebook = false;
  bool submitting = false;

  Future<void> chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
      helpText: 'রক্তদানের তারিখ নির্বাচন করুন',
    );

    if (picked != null) {
      setState(() {
        donationDate = picked;
      });
    }
  }

  Future<void> chooseDonationPhoto() async {
    if (!permissionForFacebook) {
      showMessage(
        context,
        'ছবি দেওয়ার আগে ফেসবুক পেজে ব্যবহারের অনুমতি দিন।',
        error: true,
      );
      return;
    }

    final XFile? picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (picked != null) {
      setState(() {
        donationPhoto = File(picked.path);
      });
    }
  }

  Future<void> submitDonation() async {
    if (donationDate == null) {
      showMessage(
        context,
        'রক্তদানের তারিখ নির্বাচন করুন।',
        error: true,
      );
      return;
    }

    setState(() {
      submitting = true;
    });

    try {
      String? photoUrl;

      if (donationPhoto != null) {
        photoUrl = await uploadImage(
          donationPhoto!,
          'donation_photos',
        );
      }

      await db.collection('donation_records').add({
        'donorId': widget.donorId,
        'donorName': widget.donorName,
        'donationDate': Timestamp.fromDate(donationDate!),
        'patientType': patientController.text.trim(),
        'hospital': hospitalController.text.trim(),
        'donatedThroughApp': donatedThroughApp,
        'photoUrl': photoUrl,
        'facebookPermission': permissionForFacebook,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await db.collection('donors').doc(widget.donorId).update({
        'lastDonationDate': Timestamp.fromDate(donationDate!),
        'availability': 'অনুপলব্ধ',
        'totalDonations': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        submitting = false;
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CongratulationsPage(
            donorName: widget.donorName,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        submitting = false;
      });

      showMessage(
        context,
        'রক্তদানের তথ্য সংরক্ষণ করা যায়নি।',
        error: true,
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('আজকের রক্তদান'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionTitle(
            title: 'রক্তদানের তথ্য',
            english: 'DONATION INFORMATION',
          ),

          const SizedBox(height: 12),

          DatePickerField(
  title: 'রক্তদানের তারিখ',
  english: 'DONATION DATE',
  date: donationDate,
  onTap: chooseDate,
),
          const SizedBox(height: 12),

          AppTextField(
            controller: patientController,
            label: 'রোগীর ধরন',
            english: 'PATIENT TYPE',
            icon: Icons.person,
          ),

          const SizedBox(height: 12),

          AppTextField(
            controller: hospitalController,
            label: 'হাসপাতালের নাম',
            english: 'HOSPITAL',
            icon: Icons.local_hospital,
          ),

          const SizedBox(height: 18),

          SectionTitle(
            title: 'অ্যাপের মাধ্যমে রক্তদানের ব্যবস্থা হয়েছিল?',
            english: 'DONATED THROUGH APP?',
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: ChoiceChipButton(
                  title: 'হ্যাঁ',
                  selected: donatedThroughApp == 'হ্যাঁ',
                  onTap: () {
                    setState(() {
                      donatedThroughApp = 'হ্যাঁ';
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChipButton(
                  title: 'না',
                  selected: donatedThroughApp == 'না',
                  onTap: () {
                    setState(() {
                      donatedThroughApp = 'না';
                    });
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          SectionTitle(
            title: 'রক্তদানের ছবি',
            english: 'DONATION PHOTO',
          ),

          const SizedBox(height: 10),

          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: permissionForFacebook,
            onChanged: (value) {
              setState(() {
                permissionForFacebook = value ?? false;
              });
            },
            title: Text(
              'ছবিটি ফেসবুক পেজে ব্যবহারের অনুমতি দিচ্ছি',
              style: GoogleFonts.notoSansBengali(
                fontSize: 13,
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),

          const SizedBox(height: 8),

          OutlinedButton.icon(
            onPressed: chooseDonationPhoto,
            icon: const Icon(Icons.photo_camera),
            label: Text(
              donationPhoto == null
                  ? 'রক্তদানের ছবি নির্বাচন করুন'
                  : 'ছবি পরিবর্তন করুন',
              style: GoogleFonts.notoSansBengali(),
            ),
          ),

          if (donationPhoto != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                donationPhoto!,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          ],

          const SizedBox(height: 25),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: submitting ? null : submitDonation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepRed,
                foregroundColor: Colors.white,
              ),
              child: Text(
                submitting
                    ? 'সংরক্ষণ হচ্ছে...'
                    : 'রক্তদানের তথ্য জমা দিন',
                style: GoogleFonts.notoSansBengali(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  @override
  void dispose() {
    patientController.dispose();
    hospitalController.dispose();
    super.dispose();
  }
}
// ============================================================
// CONGRATULATIONS
// ============================================================

class CongratulationsPage extends StatelessWidget {
  final String donorName;

  const CongratulationsPage({
    super.key,
    required this.donorName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.lightRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite,
                    size: 65,
                    color: AppColors.deepRed,
                  ),
                ),

                const SizedBox(height: 25),

                Text(
                  'অভিনন্দন!',
                  style: GoogleFonts.notoSansBengali(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepRed,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  donorName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansBengali(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                Text(
                  'আজ আপনি একজন মানুষের জন্য আশার আলো হয়েছেন। '
                  'আপনার এই মহৎ কাজের জন্য Chikandandi Blood Donors App পরিবারের পক্ষ থেকে আন্তরিক অভিনন্দন ও ভালোবাসা।',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansBengali(
                    fontSize: 14,
                    height: 1.7,
                    color: AppColors.grey,
                  ),
                ),

                const SizedBox(height: 30),

                Text(
                  'YOUR BLOOD CAN SAVE A LIFE',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.deepRed,
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.popUntil(
                        context,
                        (route) => route.isFirst,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepRed,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      'ড্যাশবোর্ডে ফিরে যান',
                      style: GoogleFonts.notoSansBengali(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// COMMON WIDGETS
// ============================================================

class SectionTitle extends StatelessWidget {
  final String title;
  final String english;

  const SectionTitle({
    super.key,
    required this.title,
    required this.english,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.notoSansBengali(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.dark,
          ),
        ),
        Text(
          english,
          style: GoogleFonts.poppins(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: AppColors.deepRed,
          ),
        ),
      ],
    );
  }
}

class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String english;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.english,
    required this.icon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.notoSansBengali(
        fontSize: 14,
      ),
      decoration: InputDecoration(
        prefixIcon: Icon(
          icon,
          color: AppColors.deepRed,
        ),
        label: Text(
          label,
          style: GoogleFonts.notoSansBengali(
            fontSize: 13,
          ),
        ),
        helperText: english,
        helperStyle: GoogleFonts.poppins(
          fontSize: 8,
          color: AppColors.grey,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.deepRed,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class AppDropdown extends StatelessWidget {
  final String label;
  final String english;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  const AppDropdown({
    super.key,
    required this.label,
    required this.english,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue =
        items.contains(value) ? value : null;

    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      onChanged: enabled ? onChanged : null,
      style: GoogleFonts.notoSansBengali(
        fontSize: 13,
        color: AppColors.dark,
      ),
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.arrow_drop_down_circle_outlined,
          color: AppColors.deepRed,
        ),
        label: Text(
          label,
          style: GoogleFonts.notoSansBengali(
            fontSize: 13,
          ),
        ),
        helperText: english,
        helperStyle: GoogleFonts.poppins(
          fontSize: 8,
          color: AppColors.grey,
        ),
        filled: true,
        fillColor:
            enabled ? Colors.white : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.grey.shade200,
          ),
        ),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
    );
  }
}

class DatePickerField extends StatelessWidget {
  final String title;
  final String english;
  final DateTime? date;
  final VoidCallback onTap;

  const DatePickerField({
    super.key,
    required this.title,
    required this.english,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              color: AppColors.deepRed,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansBengali(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    english,
                    style: GoogleFonts.poppins(
                      fontSize: 8,
                      color: AppColors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date == null
                        ? 'তারিখ নির্বাচন করুন'
                        : formatDate(date),
                    style: GoogleFonts.notoSansBengali(
                      fontSize: 12,
                      color: date == null
                          ? AppColors.grey
                          : AppColors.deepRed,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 15,
              color: AppColors.deepRed,
            ),
          ],
        ),
      ),
    );
  }
}

class AvailabilityButton extends StatelessWidget {
  final String title;
  final String english;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  const AvailabilityButton({
    super.key,
    required this.title,
    required this.english,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: 13,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.deepRed
              : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? AppColors.deepRed
                : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? Colors.white
                  : AppColors.deepRed,
            ),
            const SizedBox(height: 3),
            Text(
              title,
              style: GoogleFonts.notoSansBengali(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: selected
                    ? Colors.white
                    : AppColors.dark,
              ),
            ),
            Text(
              english,
              style: GoogleFonts.poppins(
                fontSize: 7,
                fontWeight: FontWeight.bold,
                color: selected
                    ? Colors.white70
                    : AppColors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChoiceChipButton extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const ChoiceChipButton({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.deepRed
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.deepRed
                : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: GoogleFonts.notoSansBengali(
              color: selected
                  ? Colors.white
                  : AppColors.dark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const ProfileInfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.lightRed,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: AppColors.deepRed,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansBengali(
                    fontSize: 10,
                    color: AppColors.grey,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.notoSansBengali(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
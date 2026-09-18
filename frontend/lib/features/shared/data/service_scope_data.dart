import 'package:flutter/material.dart';

/// Represents a step in the 'How it's done?' workflow.
class HowItsDoneStep {
  const HowItsDoneStep({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}

/// A question and answer pair for customer or worker service FAQs.
class ServiceFaq {
  const ServiceFaq({
    required this.question,
    required this.answer,
  });

  final String question;
  final String answer;
}

/// Definition for a trade/category's scope of work, boundaries, workflow and FAQs.
class CategoryScopeDefinition {
  const CategoryScopeDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.included,
    required this.excluded,
    this.equipmentNotice = 'Please provide all necessary equipments and materials for the expert.',
    this.howItsDone = const [
      HowItsDoneStep(
        title: 'Plan the Work',
        description: 'Your professional inspects the requirements and agrees on the task plan.',
        icon: Icons.assignment_outlined,
      ),
      HowItsDoneStep(
        title: 'Start Service',
        description: 'They begin with the scheduled tasks safely with verified standard tools.',
        icon: Icons.build_circle_outlined,
      ),
      HowItsDoneStep(
        title: 'Final Checks',
        description: 'Before completing, they perform a joint test and clean up the work area.',
        icon: Icons.fact_check_outlined,
      ),
    ],
    this.faqs = const [],
  });

  final String id;
  final String title;
  final IconData icon;
  final List<String> included;
  final List<String> excluded;
  final String equipmentNotice;
  final List<HowItsDoneStep> howItsDone;
  final List<ServiceFaq> faqs;
}

abstract final class ServiceScopeData {
  static const List<CategoryScopeDefinition> definitions = [
    // 1. Domestic Helper / Cleaning
    CategoryScopeDefinition(
      id: 'domestic_helper',
      title: 'House Cleaning',
      icon: Icons.cleaning_services_rounded,
      equipmentNotice: 'Please provide all necessary cleaning supplies and equipments for the expert.',
      included: [
        'Sweep and mop accessible floors & hallways',
        'Dust and wipe reachable furniture, desks & wardrobes',
        'Dust reachable walls, ceiling fans & switchboards',
        'Change or rearrange existing bedding & pillows',
        'Dispose dry and segregated household waste in bins',
        'Wipe kitchen slabs and exterior of kitchen appliances',
      ],
      excluded: [
        'Cleaning unsafe or inaccessible exterior windows & ledges',
        'Any tasks involving high ladders or working at precarious heights',
        'Moving heavy furniture, large steel almirahs, or appliances',
        'Cleaning exterior terraces, open garden soil, or compound areas',
        'Child, elderly, pet sitting, cooking, or personal medical care',
      ],
      howItsDone: [
        HowItsDoneStep(
          title: 'Plan the Work',
          description: 'Your professional plans the tasks as per your priority rooms and booking time.',
          icon: Icons.calendar_month_outlined,
        ),
        HowItsDoneStep(
          title: 'Start Cleaning',
          description: 'They begin with dry dusting, followed by mopping and surface sanitization.',
          icon: Icons.cleaning_services_outlined,
        ),
        HowItsDoneStep(
          title: 'Final Checks',
          description: 'Before finishing, they give a quick wipe and make sure everything looks tidy.',
          icon: Icons.task_alt_outlined,
        ),
      ],
      faqs: [
        ServiceFaq(
          question: 'What if the cleaning isn’t completed within the selected time?',
          answer: 'You can easily extend the service time through the app with the worker’s consent at standard pro-rata base rates.',
        ),
        ServiceFaq(
          question: 'How can I trust your service?',
          answer: 'All workers are government ID verified, police background checked, and backed by a registered Labour Cooperative Federation.',
        ),
        ServiceFaq(
          question: 'Do I need to provide all the cleaning equipment?',
          answer: 'Yes, basic cleaning materials (mop, bucket, dusters, and floor cleaner liquids) should be provided by the household.',
        ),
        ServiceFaq(
          question: 'How are the prices calculated?',
          answer: 'Prices follow the statutory fair wage floor set by the worker’s cooperative federation with transparent base rates.',
        ),
        ServiceFaq(
          question: 'How do I contact support?',
          answer: 'Support is available 24/7 via the in-app chat or SOS emergency button on your active booking screen.',
        ),
      ],
    ),

    // 2. Dusting & Wiping Sub-Category
    CategoryScopeDefinition(
      id: 'dusting_wiping',
      title: 'Dusting & Wiping',
      icon: Icons.dry_cleaning_rounded,
      equipmentNotice: 'Please provide micro-fiber cloths and surface cleaning spray.',
      included: [
        'Dust electronic items (TV, monitors, music systems)',
        'Wipe window sills, glass doors & dining tables',
        'Dust book racks, display shelves & photo frames',
        'Clean exterior of microwave, fridge & chimney',
      ],
      excluded: [
        'Dismantling electronic appliances for internal dusting',
        'Wiping fragile chandeliers or vintage antiques',
        'External glass facade cleaning over heights',
      ],
      howItsDone: [
        HowItsDoneStep(
          title: 'Surface Inspection',
          description: 'Identify delicate items and agree on cleaning priorities.',
          icon: Icons.search_rounded,
        ),
        HowItsDoneStep(
          title: 'Dust & Sanitize',
          description: 'Using dry and moist microfiber cloths systematically from top to bottom.',
          icon: Icons.dry_cleaning_outlined,
        ),
        HowItsDoneStep(
          title: 'Inspection & Signoff',
          description: 'Ensure surfaces are streak-free and well organized.',
          icon: Icons.check_circle_outline,
        ),
      ],
      faqs: [
        ServiceFaq(
          question: 'Will delicate electronics be handled safely?',
          answer: 'Yes, professionals only use dry microfiber wipes on electronics and never spray liquid directly on screens.',
        ),
      ],
    ),

    // 3. Bathroom Cleaning
    CategoryScopeDefinition(
      id: 'bathroom_cleaning',
      title: 'Bathroom Cleaning',
      icon: Icons.bathtub_rounded,
      equipmentNotice: 'Please provide bathroom cleaner, brush, and wiper.',
      included: [
        'Scrub and sanitize toilet pot, seat & flush tank',
        'Clean washbasin, mirror and bathroom tiles',
        'Scrub shower area, taps, fittings and drain trap',
        'Wipe bathroom door and accessible exhaust vent',
      ],
      excluded: [
        'Removal of deep decades-old acid etchings without special chemicals',
        'Unblocking deeply clogged main sewer pipelines',
        'Tile re-grouting or civil plumbing alterations',
      ],
      howItsDone: [
        HowItsDoneStep(
          title: 'Pre-treatment',
          description: 'Apply disinfectant solution on fittings and fixtures to dissolve hard water stains.',
          icon: Icons.water_drop_outlined,
        ),
        HowItsDoneStep(
          title: 'Scrub & Rinse',
          description: 'Thorough scrubbing of floor, tiles, basin, and WC.',
          icon: Icons.brush_outlined,
        ),
        HowItsDoneStep(
          title: 'Dry Wiper',
          description: 'Wipe mirrors, chrome fittings, and floor for a clean dry finish.',
          icon: Icons.done_all_rounded,
        ),
      ],
      faqs: [
        ServiceFaq(
          question: 'Are hard-water stains completely removed?',
          answer: 'Standard hard-water stains are thoroughly scrubbed. Severe years-old scaling may require specialized de-scaling acid not included in regular cleaning.',
        ),
      ],
    ),

    // 4. Electrician
    CategoryScopeDefinition(
      id: 'electrician',
      title: 'Electrical Services',
      icon: Icons.bolt_rounded,
      equipmentNotice: 'Worker carries standard insulated tools and multi-meter. Any replacement switches/wires to be provided or billed separately.',
      included: [
        'Diagnose circuit trips, short circuits & MCB issues',
        'Install, replace or repair switches, sockets & regulators',
        'Fan, light fixture, chandelier & bell installations',
        'Appliance power point setup and earthing checks',
        'Safe wire insulation and load testing',
      ],
      excluded: [
        'Concealed wall chasing or civil brick cutting',
        'High-tension phase line work outside the property meter',
        'Installation of heavy solar panels on high rooftops without scaffolding',
        'Working with live power lines without disconnecting main breaker',
      ],
      howItsDone: [
        HowItsDoneStep(
          title: 'Isolate & Inspect',
          description: 'Power is safely turned off at the MCB and wiring is inspected with a voltage tester.',
          icon: Icons.power_settings_new_rounded,
        ),
        HowItsDoneStep(
          title: 'Execute Repair',
          description: 'Replace faulty switches, wire terminals, or install requested electrical fixtures.',
          icon: Icons.build_outlined,
        ),
        HowItsDoneStep(
          title: 'Load Test & Earthing',
          description: 'Restore power and verify voltage, earthing, and smooth functioning.',
          icon: Icons.verified_outlined,
        ),
      ],
      faqs: [
        ServiceFaq(
          question: 'Are spare parts included in the price?',
          answer: 'No, the base price covers diagnostic & labour. Any spare parts (switches, MCBs, wires) can be provided by you or procured with customer approval.',
        ),
        ServiceFaq(
          question: 'Do I need to turn off the main power?',
          answer: 'The worker isolates the relevant circuit at the MCB before starting. Keep the main distribution board accessible and clear of clutter.',
        ),
        ServiceFaq(
          question: 'How long does a typical visit take?',
          answer: 'Most switch, socket, or fan jobs finish in about 45–90 minutes after diagnosis. Larger wiring jobs may need more time, which the worker will confirm before starting.',
        ),
        ServiceFaq(
          question: 'What if the issue is not fixed in one visit?',
          answer: 'The worker will explain findings on site. You can rebook or extend the visit through the app with transparent labour pricing.',
        ),
      ],
    ),

    // 5. Plumber
    CategoryScopeDefinition(
      id: 'plumber',
      title: 'Plumbing Services',
      icon: Icons.plumbing_rounded,
      equipmentNotice: 'Worker carries wrench, sealants, and pipe tools. Replacement taps, washers, or pipes must be provided or billed separately.',
      included: [
        'Repair leaking taps, diverters, faucets & pipe joints',
        'Unclog sinks, washbasins, bathroom floor drains & traps',
        'Install or replace sanitaryware, health faucets & flush tanks',
        'Water tank ball-valve, float valve & motor pipe connection repairs',
        'Geyser and washing machine water inlet/outlet connections',
      ],
      excluded: [
        'Digging underground street drainage or municipal main pipeline work',
        'Heavy concrete demolition or major bathroom remodeling',
        'Sewage septic tank mechanical pumping without specialized vacuum tanker',
      ],
      howItsDone: [
        HowItsDoneStep(
          title: 'Water Shut-off & Diagnosis',
          description: 'Turn off the stopcock or main valve and locate the exact leak or blockage.',
          icon: Icons.water_drop_outlined,
        ),
        HowItsDoneStep(
          title: 'Precision Fix',
          description: 'Replace gaskets, Teflon tape joints, tighten fittings, or rod out the blockage.',
          icon: Icons.plumbing_outlined,
        ),
        HowItsDoneStep(
          title: 'Pressure Test',
          description: 'Turn water back on, check under pressure for 5 minutes, ensure zero drips.',
          icon: Icons.check_circle_outline,
        ),
      ],
      faqs: [
        ServiceFaq(
          question: 'What if a pipe requires replacement inside the wall?',
          answer: 'Minor exterior piping is fixed on the spot. If wall chipping is needed, the worker will discuss the scope and extra parts before starting.',
        ),
      ],
    ),

    // 6. Carpenter
    CategoryScopeDefinition(
      id: 'carpenter',
      title: 'Carpentry Services',
      icon: Icons.carpenter_rounded,
      equipmentNotice: 'Worker carries hand tools, drill machine, and level. Screws, hinges, and wood to be provided or billed as materials.',
      included: [
        'Repair door locks, latches, handles & hinges',
        'Align wardrobe shutters, sliding channels & kitchen drawers',
        'Assemble bed frames, flat-pack furniture & dining sets',
        'Mount curtain rods, wall shelves, TV units & paintings',
        'Minor wood trimming, planing & edge leveling',
      ],
      excluded: [
        'Large-scale customized furniture manufacturing from raw wood logs on-site',
        'Spray polish or chemical lacquer coating indoors without proper ventilation',
        'Structural wooden roof beams or scaffolding erection',
      ],
      howItsDone: [
        HowItsDoneStep(
          title: 'Measurement & Markings',
          description: 'Measure dimensions using spirit levels to ensure laser-straight alignment.',
          icon: Icons.straighten_outlined,
        ),
        HowItsDoneStep(
          title: 'Fitting & Drilling',
          description: 'Precision drilling, anchor plugging, and screw tightening.',
          icon: Icons.handyman_outlined,
        ),
        HowItsDoneStep(
          title: 'Functional Check',
          description: 'Smooth latching, seamless hinge swing, and sturdy weight bearing confirmed.',
          icon: Icons.fact_check_outlined,
        ),
      ],
      faqs: [
        ServiceFaq(
          question: 'Can the carpenter assemble IKEA or online furniture?',
          answer: 'Yes! Our carpenters are trained in assembling flat-pack furniture from IKEA, Pepperfry, Urban Ladder, and Amazon.',
        ),
      ],
    ),

    // 7. Painter
    CategoryScopeDefinition(
      id: 'painter',
      title: 'Painting Services',
      icon: Icons.format_paint_rounded,
      equipmentNotice: 'Worker carries brushes and rollers. Paint, primer, and putty to be provided by customer.',
      included: [
        'Wall touch-ups, patch repairs & nail hole putty filling',
        'Single room, accent wall, or full interior emulsion painting',
        'Door, grill, and window enamel/primer coat application',
        'Masking tape protection for switches, skirting & furniture',
      ],
      excluded: [
        'Scaffolding on building exterior walls over 2 stories high',
        'Chemical waterproofing without technical civil diagnosis',
        'Heavy furniture shifting outside the apartment',
      ],
      howItsDone: [
        HowItsDoneStep(
          title: 'Masking & Surface Prep',
          description: 'Cover floors and switches; sand walls and fill nail dents with putty.',
          icon: Icons.texture_outlined,
        ),
        HowItsDoneStep(
          title: 'Prime & Paint',
          description: 'Apply even base coats followed by fine finish roller coats.',
          icon: Icons.format_paint_outlined,
        ),
        HowItsDoneStep(
          title: 'Clean Up & Reveal',
          description: 'Remove masking tape, clean minor floor splatters, and inspect finish.',
          icon: Icons.verified_outlined,
        ),
      ],
      faqs: [
        ServiceFaq(
          question: 'How do I know how much paint to buy?',
          answer: 'The worker will measure the wall square footage upon arrival and guide you on the exact litres of primer and paint required.',
        ),
      ],
    ),

    // 8. Gardener
    CategoryScopeDefinition(
      id: 'gardener',
      title: 'Gardening Services',
      icon: Icons.yard_rounded,
      equipmentNotice: 'Worker brings pruning shears and trowels. Pots, soil, fertilizer provided by customer.',
      included: [
        'Pruning, hedge trimming & weeding of flower beds',
        'Soil aeration, repotting plants & fertilizing',
        'Pest spray application (organic/prescribed spray)',
        'Balcony garden organization & watering system check',
      ],
      excluded: [
        'Tree felling or heavy trunk cutting over 10 feet high',
        'Disposal of massive tractor-loads of garden mud without municipal bin',
        'Underground landscape irrigation piping installation',
      ],
      howItsDone: [
        HowItsDoneStep(
          title: 'Inspect & Weed',
          description: 'Remove dead leaves, invasive weeds, and assess soil condition.',
          icon: Icons.eco_outlined,
        ),
        HowItsDoneStep(
          title: 'Pruning & Nourish',
          description: 'Prune overgrown foliage and add fertilizer or fresh potting mix.',
          icon: Icons.agriculture_outlined,
        ),
        HowItsDoneStep(
          title: 'Wash & Sweep',
          description: 'Clean garden pathway or balcony floor of loose soil and dry leaves.',
          icon: Icons.cleaning_services_outlined,
        ),
      ],
      faqs: [
        ServiceFaq(
          question: 'Can the gardener bring organic manure or fertilizer?',
          answer: 'Yes, during booking you can specify if you need the worker to bring compost or potting soil, which will be billed at actual cost.',
        ),
      ],
    ),
  ];

  /// Find definition by category key or ID, falling back to domestic_helper or generic scope.
  static CategoryScopeDefinition getScopeForCategory(String? categoryId) {
    if (categoryId == null || categoryId.trim().isEmpty) {
      return definitions.first;
    }
    final normalized = categoryId.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    for (final def in definitions) {
      if (def.id == normalized ||
          def.title.toLowerCase().contains(normalized) ||
          normalized.contains(def.id)) {
        return def;
      }
    }

    // Keyword fallbacks
    if (normalized.contains('clean') || normalized.contains('maid') || normalized.contains('domestic')) {
      return definitions.firstWhere((d) => d.id == 'domestic_helper');
    }
    if (normalized.contains('plumb') || normalized.contains('leak') || normalized.contains('tap')) {
      return definitions.firstWhere((d) => d.id == 'plumber');
    }
    if (normalized.contains('elect') || normalized.contains('wire') || normalized.contains('fan')) {
      return definitions.firstWhere((d) => d.id == 'electrician');
    }
    if (normalized.contains('carp') || normalized.contains('wood') || normalized.contains('furnit')) {
      return definitions.firstWhere((d) => d.id == 'carpenter');
    }
    if (normalized.contains('paint')) {
      return definitions.firstWhere((d) => d.id == 'painter');
    }
    if (normalized.contains('garden') || normalized.contains('plant')) {
      return definitions.firstWhere((d) => d.id == 'gardener');
    }

    return definitions.first;
  }

  /// Worker-specific FAQs regarding rights, equipment, and cooperative support.
  static const List<ServiceFaq> workerFaqs = [
    ServiceFaq(
      question: 'What if the customer asks for work outside what is included?',
      answer: 'Politely inform the customer that the task falls outside the standard scope agreed on Fixly. If you are comfortable performing extra tasks, use the "Add Extra Parts / Services" button in the active job console to add an agreed charge, or contact Fixly support.',
    ),
    ServiceFaq(
      question: 'What if the customer does not have the required materials/equipment?',
      answer: 'You are only expected to bring standard hand tools. For consumables or parts (like cleaning liquid, switches, pipes, paint), ask the customer to provide them or get approval in the app before purchasing.',
    ),
    ServiceFaq(
      question: 'How is my statutory fair wage protected by my Cooperative Federation?',
      answer: 'Fixly enforces a statutory minimum wage floor determined by your registered federation. No booking can undercut this wage, and cooperative members receive 100% direct payouts without commission cuts.',
    ),
    ServiceFaq(
      question: 'What if the customer cancels or is not at home after I arrive?',
      answer: 'Once you reach the location and tap "Arrived", an on-site waiting timer starts. If the customer does not respond within 15 minutes, you receive a guaranteed dispatch payout.',
    ),
    ServiceFaq(
      question: 'How do I access accidental coverage and emergency assistance?',
      answer: 'As an active cooperative member linked to e-Shram, you are covered by on-duty accidental insurance. In any emergency, tap the red SOS button in the app for immediate federation response and police/ambulance dispatch.',
    ),
  ];
}

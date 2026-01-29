/// Top home builders by metro area.
/// This data enables location-aware builder selection in the profile.

class MetroBuilders {
  /// Metro area identifiers
  static const String kansasCity = 'kansas_city';
  static const String stLouis = 'st_louis';
  static const String sacramento = 'sacramento'; // Includes Vacaville, Fairfield
  static const String detroit = 'detroit'; // Includes Grand Rapids, Traverse City
  static const String seattle = 'seattle';
  static const String billings = 'billings';
  static const String cleveland = 'cleveland';

  /// Top 30 builders in Kansas City metro area
  static const List<String> kansasCityBuilders = [
    'Summit Homes',
    'Rodrock Homes',
    'New Mark Homes',
    'Haren Companies',
    'Don Julian Builders',
    'Ashlar Homes',
    'JC Nichols Homes',
    'Bickimer Homes',
    'Heartland Homes KC',
    'Keenan Custom Homes',
    'Drees Homes',
    'McArthur Homes',
    'Prieb Homes',
    'Ashner Construction',
    'Comerio Homes',
    'Hibbs Homes',
    'Chris George Homes',
    'McClain Homes',
    'Lennar',
    'Pulte Homes',
    'Fischer & Frichtel',
    'S&K Builders',
    'Benevento Homes',
    'Harris Homes',
    'Lee Gray Homes',
    'Ruf Homes',
    'Rausch Coleman Homes',
    'Overland Homes',
    'Toll Brothers',
    'Custom Build',
  ];

  /// Top 30 builders in St. Louis metro area
  static const List<String> stLouisBuilders = [
    'Fischer & Frichtel',
    'McBride Homes',
    'Consort Homes',
    'McKelvey Homes',
    'Lombardo Homes',
    'Payne Family Homes',
    'Cf. Development',
    'Drees Homes',
    'Pulte Homes',
    'Lennar',
    'Rolwes Company',
    'Whalen Custom Homes',
    'Bridgewater Builders',
    'Bellon Construction',
    'Hibbs Homes',
    'Schafer Development',
    'Winkelmann Building',
    'Mayer & Co Homes',
    'Benton Homebuilders',
    'Sterling Custom Homes',
    'Prestige Homes',
    'Alair Homes',
    'Lifestyle Homes',
    'Clayton Premier Homes',
    'Ferguson Brothers',
    'Pinnacle Homes',
    'Hartmann Homes',
    'Kreilich Construction',
    'Toll Brothers',
    'Custom Build',
  ];

  /// Top 30 builders in Sacramento / Vacaville / Fairfield area
  static const List<String> sacramentoBuilders = [
    'Lennar',
    'KB Home',
    'Taylor Morrison',
    'Meritage Homes',
    'Beazer Homes',
    'Richmond American Homes',
    'Pulte Homes',
    'Toll Brothers',
    'Tri Pointe Homes',
    'CalAtlantic Homes',
    'Woodside Homes',
    'Elliott Homes',
    'JMC Homes',
    'Tim Lewis Communities',
    'Signature Homes',
    'Century Communities',
    'Anthem United',
    'DeNova Homes',
    'Kiper Homes',
    'K. Hovnanian Homes',
    'Granville Homes',
    'Shea Homes',
    'Van Daele Homes',
    'Silverado Homes',
    'LGI Homes',
    'D.R. Horton',
    'Brookfield Residential',
    'Trumark Homes',
    'Blue Mountain Communities',
    'Custom Build',
  ];

  /// Top 30 builders in Detroit / Grand Rapids / Traverse City area
  static const List<String> detroitBuilders = [
    'Pulte Homes',
    'Toll Brothers',
    'Lombardo Homes',
    'MJC Companies',
    'Robertson Brothers',
    'Babcock Homes',
    'Ivanhohe Huntley',
    'Allen Edwin Homes',
    'Sable Homes',
    'Arteva Homes',
    'Eastbrook Homes',
    'Heritage Building Group',
    'M/I Homes',
    'Meritage Homes',
    'Hunter Pasteur Homes',
    'HHHunt Homes',
    'Singh Development',
    'Mayberry Homes',
    'Brookstone Homes',
    'Decker Homes',
    'Infinity Homes',
    'Consort Homes MI',
    'Mark Christiansen Homes',
    'Grandville Development',
    'Blue Wave Custom Homes',
    'North Star Builders',
    'Lake Effect Homes',
    'Michiana Homes',
    'D.R. Horton',
    'Custom Build',
  ];

  /// Top 30 builders in Seattle metro area
  static const List<String> seattleBuilders = [
    'Quadrant Homes',
    'MainVue Homes',
    'Toll Brothers',
    'Richmond American Homes',
    'Lennar',
    'Pulte Homes',
    'KB Home',
    'Century Communities',
    'Tri Pointe Homes',
    'JK Monarch',
    'Shea Homes',
    'Murray Franklyn Homes',
    'Polygon Homes',
    'Harbour Homes',
    'Sundquist Homes',
    'Oakpointe Communities',
    'Meritage Homes',
    'Camwest Development',
    'D.R. Horton',
    'Thomas James Homes',
    'Conner Homes',
    'Ichijo USA',
    'Homesite',
    'Burnstead Construction',
    'Rush Residential',
    'Bennett Homes',
    'Prestige Residential',
    'Pacific Ridge Homes',
    'Belmark Homes',
    'Custom Build',
  ];

  /// Top 30 builders in Billings, MT area
  static const List<String> billingsBuilders = [
    'Blue Creek Homes',
    'Canyon Creek Homes',
    'Yellowstone Custom Homes',
    'Rimrock Construction',
    'Treasure State Homes',
    'Sterling Custom Homes',
    'Big Sky Construction',
    'Billings Home Builders',
    'Montana Homeworks',
    'Prairie Wind Homes',
    'Mountain View Builders',
    'Yellowstone Valley Homes',
    'Craftsman Homes MT',
    'Legacy Homes Montana',
    'Heritage Builders MT',
    'Rocky Mountain Homes',
    'Sunset Ridge Builders',
    'Pioneer Homes',
    'Frontier Custom Homes',
    'Alpine Construction',
    'Western Star Builders',
    'High Plains Homes',
    'Meadowlark Construction',
    'Beartooth Builders',
    'Bridger Homes',
    'Stillwater Construction',
    'Gallatin Valley Homes',
    'Northern Lights Builders',
    'Homestead Builders',
    'Custom Build',
  ];

  /// Top 30 builders in Cleveland, OH area
  static const List<String> clevelandBuilders = [
    'Pulte Homes',
    'Ryan Homes',
    'Drees Homes',
    'M/I Homes',
    'K. Hovnanian Homes',
    'Petros Homes',
    'Marhofer Realtors & Builders',
    'Schumacher Homes',
    'Rocklyn Homes',
    'Epcon Communities',
    'Wayne Homes',
    'Heartland Homes',
    'W.T. Builders',
    'Crocker Park Living',
    'Westlake Custom Homes',
    'Heritage Homes Ohio',
    'Cleveland Custom Homes',
    'Lake Erie Builders',
    'Normandy Homes',
    'Tudor Construction',
    'Brennan Builders',
    'Revere Construction',
    'Northeast Ohio Homes',
    'Infinity Homes OH',
    'Custom Craft Homes',
    'First Class Builders',
    'Emerald Homes',
    'Cardinal Homes',
    'Buckeye Custom Homes',
    'Custom Build',
  ];

  /// Mapping of metro area IDs to builder lists
  static const Map<String, List<String>> buildersByMetro = {
    kansasCity: kansasCityBuilders,
    stLouis: stLouisBuilders,
    sacramento: sacramentoBuilders,
    detroit: detroitBuilders,
    seattle: seattleBuilders,
    billings: billingsBuilders,
    cleveland: clevelandBuilders,
  };

  /// Display names for metro areas
  static const Map<String, String> metroDisplayNames = {
    kansasCity: 'Kansas City',
    stLouis: 'St. Louis',
    sacramento: 'Sacramento / Vacaville / Fairfield',
    detroit: 'Detroit / Grand Rapids / Traverse City',
    seattle: 'Seattle',
    billings: 'Billings, MT',
    cleveland: 'Cleveland, OH',
  };

  /// Detect metro area from address or city name
  static String? detectMetroArea(String? address) {
    if (address == null || address.isEmpty) return null;

    final lower = address.toLowerCase();

    // Kansas City area (MO/KS)
    if (_matchesAny(lower, [
      'kansas city', 'overland park', 'olathe', 'shawnee', 'lenexa',
      'lee\'s summit', 'leawood', 'liberty', 'blue springs', 'independence',
      'gardner', 'raymore', 'belton', 'grandview', 'raytown',
      'prairie village', 'merriam', 'mission', 'roeland park',
      ', ks', ', mo', 'johnson county', 'jackson county', 'wyandotte',
    ])) {
      return kansasCity;
    }

    // St. Louis area
    if (_matchesAny(lower, [
      'st. louis', 'st louis', 'saint louis', 'chesterfield', 'creve coeur',
      'clayton', 'kirkwood', 'webster groves', 'ballwin', 'manchester',
      'wildwood', 'eureka', 'o\'fallon', 'wentzville', 'st. charles',
      'st charles', 'florissant', 'hazelwood', 'maryland heights',
      'edwardsville', 'collinsville', 'belleville',
    ])) {
      return stLouis;
    }

    // Sacramento / Vacaville / Fairfield area
    if (_matchesAny(lower, [
      'sacramento', 'vacaville', 'fairfield', 'elk grove', 'roseville',
      'folsom', 'rocklin', 'lincoln', 'davis', 'woodland', 'west sacramento',
      'rancho cordova', 'citrus heights', 'carmichael', 'fair oaks',
      'natomas', 'arden', 'carmichael', 'dixon', 'suisun', 'vallejo',
      'benicia', 'napa', 'yolo county', 'solano county', 'placer county',
    ])) {
      return sacramento;
    }

    // Detroit / Grand Rapids / Traverse City area
    if (_matchesAny(lower, [
      'detroit', 'grand rapids', 'traverse city', 'ann arbor', 'lansing',
      'troy', 'sterling heights', 'warren', 'livonia', 'dearborn',
      'farmington', 'novi', 'canton', 'plymouth', 'northville',
      'bloomfield', 'birmingham', 'royal oak', 'berkley', 'ferndale',
      'wyoming', 'kentwood', 'holland', 'muskegon', 'kalamazoo',
      'battle creek', 'portage', 'midland', 'saginaw', 'flint',
      'michigan', ', mi',
    ])) {
      return detroit;
    }

    // Seattle area
    if (_matchesAny(lower, [
      'seattle', 'bellevue', 'redmond', 'kirkland', 'tacoma', 'everett',
      'kent', 'renton', 'federal way', 'auburn', 'sammamish', 'issaquah',
      'woodinville', 'bothell', 'lynnwood', 'edmonds', 'shoreline',
      'burien', 'tukwila', 'seatac', 'mercer island', 'bainbridge',
      'olympia', 'lacey', 'puyallup', 'lakewood', 'bonney lake',
      'king county', 'pierce county', 'snohomish', ', wa',
    ])) {
      return seattle;
    }

    // Billings, MT area
    if (_matchesAny(lower, [
      'billings', 'laurel', 'hardin', 'red lodge', 'columbus',
      'livingston', 'bozeman', 'big timber', 'miles city',
      'yellowstone county', 'montana', ', mt',
    ])) {
      return billings;
    }

    // Cleveland, OH area
    if (_matchesAny(lower, [
      'cleveland', 'akron', 'parma', 'lakewood', 'euclid', 'mentor',
      'strongsville', 'westlake', 'north olmsted', 'solon', 'brunswick',
      'medina', 'north royalton', 'avon', 'avon lake', 'rocky river',
      'bay village', 'beachwood', 'shaker heights', 'cleveland heights',
      'university heights', 'mayfield', 'willoughby', 'chagrin falls',
      'cuyahoga', 'lorain', 'elyria', 'oberlin', 'canton', 'massillon',
      ', oh',
    ])) {
      return cleveland;
    }

    return null;
  }

  /// Helper to check if text matches any of the patterns
  static bool _matchesAny(String text, List<String> patterns) {
    return patterns.any((p) => text.contains(p));
  }

  /// Get builders for a metro area, with fallback to national builders
  static List<String> getBuildersForMetro(String? metroId) {
    if (metroId != null && buildersByMetro.containsKey(metroId)) {
      return buildersByMetro[metroId]!;
    }
    // Fallback to major national builders
    return nationalBuilders;
  }

  /// National builders (fallback when metro not detected)
  static const List<String> nationalBuilders = [
    'D.R. Horton',
    'Lennar',
    'Pulte Homes',
    'NVR / Ryan Homes',
    'Toll Brothers',
    'Meritage Homes',
    'KB Home',
    'Taylor Morrison',
    'Century Communities',
    'Tri Pointe Homes',
    'Dream Finders Homes',
    'M/I Homes',
    'Shea Homes',
    'Beazer Homes',
    'Ashton Woods',
    'Richmond American Homes',
    'Mattamy Homes',
    'K. Hovnanian Homes',
    'Starlight Homes',
    'LGI Homes',
    'Smith Douglas Homes',
    'Stanley Martin Homes',
    'Drees Homes',
    'Maronda Homes',
    'CalAtlantic Homes',
    'Woodside Homes',
    'David Weekley Homes',
    'Eastwood Homes',
    'McGuyer Homebuilders',
    'Custom Build',
  ];
}

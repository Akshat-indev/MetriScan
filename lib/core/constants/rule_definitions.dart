// Coverage of Legal Metrology (Packaged Commodities) Rules, 2011 — Rule 6
// All regex patterns, keyword anchors, and thresholds used by the rule engine.

/// Minimum pixel-height-to-image-width ratio for text to be considered legible.
/// Blocks below this threshold are flagged as potentially too small.
// Conservative v1 screen heuristic: only flag extremely small OCR lines.
const double kMinFontSizeRatio = 0.004;

/// Burst frame count for best-frame selection per capture tap.
const int kBurstFrameCount = 5;

/// Maximum number of back-label photos.
const int kMaxBackPhotos = 3;

/// Minimum number of back-label photos before "Done" is enabled.
const int kMinBackPhotos = 1;

/// Sharpness score threshold: frames below this are discarded before selection.
const double kMinSharpnessScore = 15.0;

/// Boundary stability: how many consecutive stable frames before auto-capture hint.
const int kBoundaryStableFrames = 8;

/// Exponential moving average alpha for boundary corner smoothing.
const double kBoundaryEmaAlpha = 0.35;

/// Pixel margin to consider a text block as "clipped" against image border.
const int kClippingMarginPx = 8;

// ---------------------------------------------------------------------------
// Regex patterns
// ---------------------------------------------------------------------------

/// MRP detection — matches "MRP", "M.R.P", "M.F.P" followed by optional currency symbol
/// and numeric value./// MRP value — either anchored by keyword or just a standalone currency pattern.
final RegExp kMrpRegex = RegExp(
  r'(?:(?:MRP|M\.R\.P\.?|M\.F\.P\.?|MAXIMUM RETAIL PRICE)\s*[:\-]?\s*[₹Rs\.R5\s]*|[₹Rs\.R5]+\s*)(\d+[.,]?\d{2})\b',
  caseSensitive: false,
);

/// Net quantity — numeric value with SI unit.
final RegExp kNetQuantityRegex = RegExp(
  r'(\d+\.?\d*)\s*(g|gm|gms|kg|ml|l|ltr|litre|litres|oz|pcs|pieces)\b',
  caseSensitive: false,
);

/// Manufacturing / packing date patterns.
final RegExp kMfgDateRegex = RegExp(
  r'\d{2}[\/\-\.\s]\d{2}[\/\-\.\s]\d{2,4}|'
  r'(0?[1-9]|1[0-2])[\/\-\.\s]\d{2,4}|'
  r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[\s,\.]+\d{2,4}',
  caseSensitive: false,
);

/// Expiry / best-before date patterns (same format as mfg date).
final RegExp kExpiryDateRegex = RegExp(
  r'\d{2}[\/\-\.\s]\d{2}[\/\-\.\s]\d{2,4}|'
  r'(0?[1-9]|1[0-2])[\/\-\.\s]\d{2,4}|'
  r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[\s,\.]+\d{2,4}',
  caseSensitive: false,
);

/// FSSAI 14-digit license number (allow OCR spacing/dots between digits).
final RegExp kFssaiNumberRegex = RegExp(
  r'\d[\d\s\.]{12,18}\d',
);

/// Phone number — 10+ digits with optional separators.
final RegExp kPhoneRegex = RegExp(
  r'(\+?91[\s\-]?)?[6-9]\d{2}[\s\-]?\d{3}[\s\-]?\d{4}|'
  r'1[89]00[\s\-]?\d{3}[\s\-]?\d{4}|'
  r'\d{2,5}[\s\-]\d{6,8}',
);

/// Email address.
final RegExp kEmailRegex = RegExp(
  r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
);

/// Lot number value — alphanumeric with separators and optional time component.
final RegExp kLotValueRegex = RegExp(
  r'[A-Z0-9][A-Z0-9\-\/\._]{1,30}(?:\s+\d{2}:\d{2})?',
  caseSensitive: false,
);

/// USP value — currency + optional "per" + unit.
final RegExp kUspValueRegex = RegExp(
  r'[₹Rs\.INR\s]*(\d+\.?\d*)\s*(per|\/)\s*(g|gm|gram|grams|kg|kilogram|ml|l|ltr|100g|100ml|piece|pcs)\b',
  caseSensitive: false,
);

// ---------------------------------------------------------------------------
// Keyword anchors (lower-case for case-insensitive comparison)
// ---------------------------------------------------------------------------

const List<String> kMfgKeywords = [
  'mfd by', 'mfd. by', 'manufactured by', 'mfr.', 'packed by', 'pkd by',
  'pkd. by', 'manufactured and packed by', 'manufactured & packed by',
];

const List<String> kPackerKeywords = [
  'packed by', 'pkd by', 'pkd. by', 'packing by',
];

const List<String> kImporterKeywords = [
  'imported by', 'importer', 'sole importer',
];

const List<String> kConsumerCareKeywords = [
  'customer care', 'consumer care', 'consumer complaint',
  'consumer grievance', 'helpline', 'toll free', 'for queries',
  'for complaints',
];

const List<String> kFssaiKeywords = [
  'fssai', 'lic no', 'lic. no', 'license no', 'licence no',
  'food license', 'fssai lic', 'fssai license',
];

const List<String> kLotKeywords = [
  'lot no', 'lot number', 'lot no.', 'lot#', 'lot :', 'lot:',
  'batch no', 'batch number', 'batch no.', 'batch#', 'batch:', 
  'l. no', 'l no', 'ln no',
];

const List<String> kMfgDateKeywords = [
  'mfg', 'mfd', 'mfg date', 'mfd date', 'manufactured',
  'packed', 'pkd', 'mfg.', 'mfd.',
];

const List<String> kExpiryKeywords = [
  'best before', 'use by', 'expiry', 'exp', 'exp date',
  'bb', 'best before date', 'use before', 'expires on',
];

const List<String> kNetQtyKeywords = [
  'net wt', 'net weight', 'net qty', 'net quantity',
  'net vol', 'net volume', 'net content', 'contents',
  'net wt.', 'net weight :', 'net content :',
];

const List<String> kMrpKeywords = [
  'mrp', 'm.r.p', 'm.r.p.', 'maximum retail price',
];

const List<String> kCountryKeywords = [
  'country of origin', 'made in', 'product of', 'origin :',
];

const List<String> kIngredientsKeywords = [
  'ingredients', 'ingredient', 'contains', 'composition',
];

/// Keywords that indicate a new section on the back label.
const List<String> kSectionBoundaryKeywords = [
  'nutritional information',
  'nutrition facts',
  'allergen',
  'allergy advice',
  'storage instructions',
  'store in',
  'manufactured by',
  'marketed by',
  'best before',
  'use by',
  'directions for use',
  'how to use',
  'warning',
  'caution',
  'fssai',
  'batch no',
  'lot no',
  'ingredients',
  'mrp',
  'net quantity',
  'net wt',
  'customer care',
  'consumer care'
];

/// Fields considered mandatory under Rule 6 for the compliance score.
const List<String> kMandatoryFields = [
  'product_name',
  'manufacturer',
  'net_quantity',
  'mrp',
  'mfg_date',
  'consumer_care',
  'lot_number',
];

/// Fields that are mandatory only in specific contexts.
const List<String> kConditionalFields = [
  'expiry_date',     // mandatory if product can become unfit
  'fssai_license',   // mandatory for food products
  'country_of_origin', // mandatory for imported goods
  'importer',        // mandatory for imported goods
];

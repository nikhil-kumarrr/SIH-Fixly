/// Display helper for worker/service ratings — never invent dummy stars.
String formatRating(double? rating, {String empty = 'New'}) {
  if (rating == null || rating <= 0) return empty;
  return rating.toStringAsFixed(1);
}

/// Example category lists offered in the setup wizard. They are only
/// suggestions: no VAT rate is attached, the user picks one per category.
class CategoryTemplate {
  final String title;
  final List<String> names;
  const CategoryTemplate(this.title, this.names);

  static const restaurant = CategoryTemplate(
      'Restaurang (exempel)', ['Mat', 'Konfektyr', 'Tobak', 'Öl', 'Sprit', 'Vin', 'Cider']);
  static const shop =
      CategoryTemplate('Butik (exempel)', ['Livsmedel', 'Dryck', 'Tobak', 'Övrigt']);
  static const empty = CategoryTemplate('Börja med en tom lista', []);

  static const all = [restaurant, shop, empty];
}

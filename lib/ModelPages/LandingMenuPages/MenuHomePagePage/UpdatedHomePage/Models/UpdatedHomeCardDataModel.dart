import 'dart:convert';

class UpdatedHomeCardDataModel {
  final dynamic axpCardsid;
  final String? cardtype;
  final String? cardname;
  final String? cardicon;
  final String? charttype;
  final String? pluginname;
  final String? htmlEditorCard;
  final String? cardDatasource;
  final String? width;
  final String? height;
  final dynamic autorefresh;
  final String? context;
  final dynamic orderno;
  dynamic carddata;

  UpdatedHomeCardDataModel({
    required this.axpCardsid,
    required this.cardtype,
    required this.cardname,
    required this.cardicon,
    required this.charttype,
    required this.pluginname,
    required this.htmlEditorCard,
    required this.cardDatasource,
    required this.width,
    required this.height,
    required this.autorefresh,
    required this.context,
    required this.orderno,
    required this.carddata,
  });

  factory UpdatedHomeCardDataModel.fromRawJson(String str) =>
      UpdatedHomeCardDataModel.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory UpdatedHomeCardDataModel.fromJson(Map<String, dynamic> json) {
    List<dynamic> parseCardData(dynamic data) {
      if (data == null) return [];

      if (data is List) return data;

      if (data is String && data.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is List) {
            return decoded;
          }
        } catch (e) {
          return [];
        }
      }

      return [];
    }

    return UpdatedHomeCardDataModel(
      axpCardsid: json["axp_cardsid"],
      cardtype: json["cardtype"],
      cardname: json["cardname"],
      cardicon: json["cardicon"],
      charttype: json["charttype"],
      pluginname: json["pluginname"] ?? '',
      htmlEditorCard: json["html_editor_card"],
      cardDatasource: json["card_datasource"],
      width: json["width"],
      height: json["height"],
      autorefresh: json["autorefresh"],
      context: json["context"],
      orderno: json["orderno"],
      carddata: parseCardData(json["carddata"] ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        "axp_cardsid": axpCardsid,
        "cardtype": cardtype,
        "cardname": cardname,
        "cardicon": cardicon,
        "charttype": charttype,
        "pluginname": pluginname,
        "html_editor_card": htmlEditorCard,
        "card_datasource": cardDatasource,
        "width": width,
        "height": height,
        "autorefresh": autorefresh,
        "context": context,
        "orderno": orderno,
        "carddata": carddata,
      };
}

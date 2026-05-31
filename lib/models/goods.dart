class Goods {
  final int? id;
  final String barcode;
  final String goodsName;
  final String? brand;
  final String? spec;
  final String? goodsImg;
  final double? purchasePrice;
  final double sellPrice;
  final String? remark;
  final DateTime createTime;
  final DateTime updateTime;

  Goods({
    this.id,
    required this.barcode,
    required this.goodsName,
    this.brand,
    this.spec,
    this.goodsImg,
    this.purchasePrice,
    required this.sellPrice,
    this.remark,
    required this.createTime,
    required this.updateTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'goods_name': goodsName,
      'brand': brand,
      'spec': spec,
      'goods_img': goodsImg,
      'purchase_price': purchasePrice,
      'sell_price': sellPrice,
      'remark': remark,
      'create_time': createTime.toIso8601String(),
      'update_time': updateTime.toIso8601String(),
    };
  }

  factory Goods.fromMap(Map<String, dynamic> map) {
    return Goods(
      id: map['id'] as int?,
      barcode: map['barcode'] as String,
      goodsName: map['goods_name'] as String,
      brand: _toStr(map['brand']),
      spec: _toStr(map['spec']),
      goodsImg: _toStr(map['goods_img']),
      purchasePrice: _toDouble(map['purchase_price']),
      sellPrice: _toDouble(map['sell_price']) ?? 0,
      remark: _toStr(map['remark']),
      createTime: DateTime.parse(map['create_time'] as String),
      updateTime: DateTime.parse(map['update_time'] as String),
    );
  }

  /// 安全转换为空字符串或 null
  static String? _toStr(dynamic value) {
    if (value == null) return null;
    if (value is String && value.trim().isEmpty) return null;
    return value.toString().trim();
  }

  /// 安全转换为 double，处理 null、空字符串、num 类型
  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      if (value.trim().isEmpty) return null;
      return double.tryParse(value.trim());
    }
    return null;
  }

  Goods copyWith({
    int? id,
    String? barcode,
    String? goodsName,
    String? brand,
    String? spec,
    String? goodsImg,
    double? purchasePrice,
    double? sellPrice,
    String? remark,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    return Goods(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      goodsName: goodsName ?? this.goodsName,
      brand: brand ?? this.brand,
      spec: spec ?? this.spec,
      goodsImg: goodsImg ?? this.goodsImg,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellPrice: sellPrice ?? this.sellPrice,
      remark: remark ?? this.remark,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
    );
  }
}

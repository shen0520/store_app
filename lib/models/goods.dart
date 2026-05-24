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
      brand: map['brand'] as String?,
      spec: map['spec'] as String?,
      goodsImg: map['goods_img'] as String?,
      purchasePrice: map['purchase_price'] != null
          ? (map['purchase_price'] as num).toDouble()
          : null,
      sellPrice: (map['sell_price'] as num).toDouble(),
      remark: map['remark'] as String?,
      createTime: DateTime.parse(map['create_time'] as String),
      updateTime: DateTime.parse(map['update_time'] as String),
    );
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

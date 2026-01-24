import 'package:flutter/material.dart';
import 'package:aloeplayer/services/membership_service.dart';
import 'package:url_launcher/url_launcher.dart';

// 动态获取会员详情与产品的对话框
class MembershipDetailsDialog extends StatefulWidget {
  final MembershipService membershipService;

  const MembershipDetailsDialog({Key? key, required this.membershipService})
      : super(key: key);

  @override
  _MembershipDetailsDialogState createState() =>
      _MembershipDetailsDialogState();
}

class _MembershipDetailsDialogState extends State<MembershipDetailsDialog> {
  bool _isLoading = true;
  // List<Product> _products = []; // 暂时隐藏产品列表
  Map<String, List<Subscription>> _subscriptions = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // final products = await widget.membershipService.fetchProducts(); // 暂时不获取产品列表
      final subs = await widget.membershipService.fetchMySubscriptions();
      if (mounted) {
        setState(() {
          // _products = products; // 暂时不设置产品列表
          _subscriptions = subs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      print('Error loading membership data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 查找当前有效订阅
    Subscription? activeSub;
    if (_subscriptions.containsKey('active_subscriptions') &&
        _subscriptions['active_subscriptions']!.isNotEmpty) {
      activeSub = _subscriptions['active_subscriptions']!.first;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '会员服务',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      // 当前状态卡片
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: activeSub != null
                              ? Colors.green.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: activeSub != null
                                ? Colors.green.withOpacity(0.3)
                                : Colors.grey.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeSub != null
                                  ? '当前订阅: ${activeSub.productName}'
                                  : '当前状态: 免费用户',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: activeSub != null
                                    ? Colors.green[800]
                                    : Colors.grey[800],
                              ),
                            ),
                            if (activeSub != null) ...[
                              SizedBox(height: 4),
                              Text(
                                '有效期至: ${activeSub.endDate.year}-${activeSub.endDate.month}-${activeSub.endDate.day}',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[700]),
                              ),
                            ] else ...[
                              SizedBox(height: 4),
                              Text('升级会员解锁更多功能',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey[600])),
                            ]
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                      // ========== 订阅套餐表格（暂时隐藏，需要时取消注释） ==========
                      // Row(
                      //   children: [
                      //     Text(
                      //       '订阅套餐',
                      //       style: TextStyle(
                      //         fontSize: 16,
                      //         fontWeight: FontWeight.bold,
                      //       ),
                      //     ),
                      //     SizedBox(width: 8),
                      //     Text(
                      //       '(IAP暂未开通)',
                      //       style: TextStyle(
                      //         fontSize: 14,
                      //         color: Colors.orange[700],
                      //         fontWeight: FontWeight.w500,
                      //       ),
                      //     ),
                      //   ],
                      // ),
                      // SizedBox(height: 12),
                      // Flexible(
                      //   child: ListView.builder(
                      //     shrinkWrap: true,
                      //     itemCount: _products.length,
                      //     itemBuilder: (context, index) {
                      //       final product = _products[index];
                      //       return Padding(
                      //         padding: EdgeInsets.only(bottom: 12),
                      //         child: Container(
                      //           decoration: BoxDecoration(
                      //             border: Border.all(color: Colors.grey[300]!),
                      //             borderRadius: BorderRadius.circular(12),
                      //           ),
                      //           child: Padding(
                      //             padding: EdgeInsets.all(16),
                      //             child: Row(
                      //               mainAxisAlignment:
                      //                   MainAxisAlignment.spaceBetween,
                      //               children: [
                      //                 Expanded(
                      //                   child: Column(
                      //                     crossAxisAlignment:
                      //                         CrossAxisAlignment.start,
                      //                     children: [
                      //                       Text(
                      //                         product.name,
                      //                         style: TextStyle(
                      //                           fontSize: 16,
                      //                           fontWeight: FontWeight.bold,
                      //                         ),
                      //                       ),
                      //                       SizedBox(height: 4),
                      //                       Text(
                      //                         product.description,
                      //                         style: TextStyle(
                      //                           fontSize: 12,
                      //                           color: Colors.grey[600],
                      //                         ),
                      //                       ),
                      //                     ],
                      //                   ),
                      //                 ),
                      //                 SizedBox(width: 12),
                      //                 Column(
                      //                   crossAxisAlignment:
                      //                       CrossAxisAlignment.end,
                      //                   children: [
                      //                     Text(
                      //                       '¥${product.price}',
                      //                       style: TextStyle(
                      //                         fontSize: 18,
                      //                         fontWeight: FontWeight.bold,
                      //                         color: Theme.of(context)
                      //                             .primaryColor,
                      //                       ),
                      //                     ),
                      //                     SizedBox(height: 8),
                      //                     ElevatedButton(
                      //                       onPressed: null, // Disabled
                      //                       style: ElevatedButton.styleFrom(
                      //                         backgroundColor: Colors.grey[300],
                      //                         foregroundColor: Colors.grey[600],
                      //                         disabledBackgroundColor:
                      //                             Colors.grey[300],
                      //                         disabledForegroundColor:
                      //                             Colors.grey[600],
                      //                         padding: EdgeInsets.symmetric(
                      //                             horizontal: 16, vertical: 8),
                      //                         minimumSize: Size(0, 32),
                      //                         shape: RoundedRectangleBorder(
                      //                           borderRadius:
                      //                               BorderRadius.circular(16),
                      //                         ),
                      //                       ),
                      //                       child: Text('购买'),
                      //                     ),
                      //                   ],
                      //                 ),
                      //               ],
                      //             ),
                      //           ),
                      //         ),
                      //       );
                      //     },
                      //   ),
                      // ),
                      // ========== 暂无套餐提示（临时显示，启用上面代码时删除此部分） ==========
                      Container(
                        width: double.infinity,
                        padding:
                            EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 48,
                              color: Colors.orange[700],
                            ),
                            SizedBox(height: 16),
                            Text(
                              '暂无可供购买的套餐',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[800],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'IAP功能暂未开通',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                      // 支持作者按钮
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final url =
                                Uri.parse('https://afdian.com/a/aloereed');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url,
                                  mode: LaunchMode.externalApplication);
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('无法打开链接')),
                                );
                              }
                            }
                          },
                          icon: Icon(Icons.favorite),
                          label: Text('支持作者'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink[400],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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

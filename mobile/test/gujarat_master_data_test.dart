import 'package:flutter_test/flutter_test.dart';
import 'package:setumitra/models/gujarat_master_data.dart';

void main() {
  group('GujaratMasterData (Master Data priority)', () {
    test('resolves અમદાવાદ to the official exonym AHMEDABAD', () {
      expect(GujaratMasterData.lookupPlaceName('અમદાવાદ'), 'AHMEDABAD');
    });

    test('resolves બોટાદ to BOTAD', () {
      expect(GujaratMasterData.lookupPlaceName('બોટાદ'), 'BOTAD');
    });

    test('resolves the state name ગુજરાત to GUJARAT', () {
      expect(GujaratMasterData.lookupPlaceName('ગુજરાત'), 'GUJARAT');
      expect(GujaratMasterData.isStateName('ગુજરાત'), isTrue);
      expect(GujaratMasterData.isStateName('gujarat'), isTrue);
    });

    test('recognises an already-English district name case-insensitively', () {
      expect(GujaratMasterData.lookupPlaceName('ahmedabad'), 'AHMEDABAD');
      expect(GujaratMasterData.lookupPlaceName('Rajkot'), 'RAJKOT');
    });

    test('recognises known English spelling aliases', () {
      expect(GujaratMasterData.lookupPlaceName('Mehsana'), 'MAHESANA');
      expect(GujaratMasterData.lookupPlaceName('Kachchh'), 'KUTCH');
      expect(GujaratMasterData.lookupPlaceName('The Dangs'), 'DANG');
    });

    test('returns null for a value that is not Gujarat or one of its districts', () {
      expect(GujaratMasterData.lookupPlaceName('Mumbai'), isNull);
      expect(GujaratMasterData.lookupPlaceName(''), isNull);
    });

    test('exposes exactly 33 canonical districts', () {
      expect(GujaratMasterData.allDistrictsEnglish.length, 33);
      expect(GujaratMasterData.allDistrictsEnglish, contains('AHMEDABAD'));
      expect(GujaratMasterData.allDistrictsEnglish, contains('VALSAD'));
    });
  });
}

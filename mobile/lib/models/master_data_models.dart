/// Master Data models -- reusable records so verified data doesn't need
/// re-entry across forms, per the pre-development audit's "remaining
/// (non-architecture) items" and the original requirements' Master Data
/// section. Each model maps 1:1 to a SQLite table created by
/// DatabaseService.
library;

class EstablishmentMaster {
  final int? id;
  final String panNumber;
  final String gstin;
  final String establishmentName;
  final String headOfficeAddress;
  final String pincode;
  final String einNumber;
  final String typeOfOwnership;
  final String typeOfEstablishment;
  // Added for Contacts & Excel export (v4 requirements Settings item 5).
  // mobileNumber/emailId are sourced from the existing
  // ShramsetuFormModel.mobile_number/email_id fields (already part of the
  // Registration form -- these are NOT new form fields, only new Master
  // Data columns). username/password have NO source in the OCR/
  // Registration flow at all -- they're Shramsetu PORTAL LOGIN
  // credentials, a separate concept -- and are entered/edited directly in
  // the Contacts export screen, not derived from any form.
  final String mobileNumber;
  final String emailId;
  final String username;
  final String password;
  final String createdAt;
  final String updatedAt;

  EstablishmentMaster({
    this.id,
    required this.panNumber,
    required this.gstin,
    required this.establishmentName,
    required this.headOfficeAddress,
    required this.pincode,
    this.einNumber = '',
    this.typeOfOwnership = '',
    this.typeOfEstablishment = '',
    this.mobileNumber = '',
    this.emailId = '',
    this.username = '',
    this.password = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'pan_number': panNumber,
        'gstin': gstin,
        'establishment_name': establishmentName,
        'head_office_address': headOfficeAddress,
        'pincode': pincode,
        'ein_number': einNumber,
        'type_of_ownership': typeOfOwnership,
        'type_of_establishment': typeOfEstablishment,
        'mobile_number': mobileNumber,
        'email_id': emailId,
        'username': username,
        'password': password,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory EstablishmentMaster.fromMap(Map<String, dynamic> map) => EstablishmentMaster(
        id: map['id'] as int?,
        panNumber: map['pan_number'] as String? ?? '',
        gstin: map['gstin'] as String? ?? '',
        establishmentName: map['establishment_name'] as String? ?? '',
        headOfficeAddress: map['head_office_address'] as String? ?? '',
        pincode: map['pincode'] as String? ?? '',
        einNumber: map['ein_number'] as String? ?? '',
        typeOfOwnership: map['type_of_ownership'] as String? ?? '',
        typeOfEstablishment: map['type_of_establishment'] as String? ?? '',
        mobileNumber: map['mobile_number'] as String? ?? '',
        emailId: map['email_id'] as String? ?? '',
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
        createdAt: map['created_at'] as String? ?? '',
        updatedAt: map['updated_at'] as String? ?? '',
      );
}

class AuthorizedPersonMaster {
  final int? id;
  final String identityNumber;
  final String name;
  final String dob;
  final String permanentAddress;
  final String designation;
  final String createdAt;
  final String updatedAt;

  AuthorizedPersonMaster({
    this.id,
    required this.identityNumber,
    required this.name,
    this.dob = '',
    this.permanentAddress = '',
    this.designation = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'identity_number': identityNumber,
        'name': name,
        'dob': dob,
        'permanent_address': permanentAddress,
        'designation': designation,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory AuthorizedPersonMaster.fromMap(Map<String, dynamic> map) => AuthorizedPersonMaster(
        id: map['id'] as int?,
        identityNumber: map['identity_number'] as String? ?? '',
        name: map['name'] as String? ?? '',
        dob: map['dob'] as String? ?? '',
        permanentAddress: map['permanent_address'] as String? ?? '',
        designation: map['designation'] as String? ?? '',
        createdAt: map['created_at'] as String? ?? '',
        updatedAt: map['updated_at'] as String? ?? '',
      );
}

class BankDetailsMaster {
  final int? id;
  final String bankName;
  final String ifsc;
  final String accountNumber;
  final String createdAt;
  final String updatedAt;

  BankDetailsMaster({
    this.id,
    required this.bankName,
    required this.ifsc,
    required this.accountNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'bank_name': bankName,
        'ifsc': ifsc,
        'account_number': accountNumber,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory BankDetailsMaster.fromMap(Map<String, dynamic> map) => BankDetailsMaster(
        id: map['id'] as int?,
        bankName: map['bank_name'] as String? ?? '',
        ifsc: map['ifsc'] as String? ?? '',
        accountNumber: map['account_number'] as String? ?? '',
        createdAt: map['created_at'] as String? ?? '',
        updatedAt: map['updated_at'] as String? ?? '',
      );
}

class PrincipalEmployerMaster {
  final int? id;
  final String einSelected;
  final String registrationNo;
  final String name;
  final String address;
  final String district;
  final String taluka;
  final String pincode;
  final String createdAt;
  final String updatedAt;

  PrincipalEmployerMaster({
    this.id,
    required this.einSelected,
    this.registrationNo = '',
    required this.name,
    required this.address,
    this.district = '',
    this.taluka = '',
    this.pincode = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'ein_selected': einSelected,
        'registration_no': registrationNo,
        'name': name,
        'address': address,
        'district': district,
        'taluka': taluka,
        'pincode': pincode,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory PrincipalEmployerMaster.fromMap(Map<String, dynamic> map) => PrincipalEmployerMaster(
        id: map['id'] as int?,
        einSelected: map['ein_selected'] as String? ?? '',
        registrationNo: map['registration_no'] as String? ?? '',
        name: map['name'] as String? ?? '',
        address: map['address'] as String? ?? '',
        district: map['district'] as String? ?? '',
        taluka: map['taluka'] as String? ?? '',
        pincode: map['pincode'] as String? ?? '',
        createdAt: map['created_at'] as String? ?? '',
        updatedAt: map['updated_at'] as String? ?? '',
      );
}

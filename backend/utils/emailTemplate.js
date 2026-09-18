export const generateOtpEmailHtml = (otp) => {
    return `
    <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; background: #f4f6f8; padding: 40px 20px; border-radius: 12px;">
        <div style="background-color: #ffffff; padding: 40px 30px; border-radius: 16px; box-shadow: 0 8px 20px rgba(0,0,0,0.05); text-align: center;">

            <!-- Static Logo -->
             <!-- <img src="https://res.cloudinary.com/vaibhavjain/image/upload/v1787750142/qdcck1uvkmcehnbhtqyi.png" alt="Company Logo" style="max-width: 150px; margin-bottom: 20px;" /> -->

            <!-- Title -->
            <h2 style="color: #1a1a1a; margin-bottom: 10px; font-size: 24px; font-weight: 600;">
                Verify Your Fixly Account
            </h2>

            <!-- Message -->
            <p style="color: #555555; font-size: 16px; margin-bottom: 30px; line-height: 1.6;">
                Use the verification code below to securely access your account. This code is valid for <strong>5 minutes</strong>.
            </p>

            <!-- OTP Box -->
            <div style="background-color: #f0f7ff; border: 2px solid #2563eb; border-radius: 10px; padding: 20px; margin-bottom: 30px; display: inline-block;">
                <!-- Added inline styles to prevent Gmail from treating it as a phone number/link -->
                <span style="font-size: 36px; font-weight: bold; color: #2563eb; letter-spacing: 6px; text-decoration: none; unicode-bidi: embed;">${otp}</span>
            </div>

            <!-- Footer -->
            <p style="color: #94a3b8; font-size: 13px; margin-top: 20px;">
                If you didn’t request this code, please ignore this email.<br/>
                &copy; 2026 Fixly. All rights reserved.
            </p>
        </div>
    </div>
    `;
};


// export const generateOtpEmailHtml = (otp) => {
//     return `
//     <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; background: linear-gradient(135deg, #fdfbfb 0%, #ebedee 100%); padding: 40px 20px; border-radius: 12px;">
//         <div style="background-color: #ffffff; padding: 40px 30px; border-radius: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.05); text-align: center;">
//             <h2 style="color: #1a1a1a; margin-bottom: 10px; font-size: 24px;">Verify Your Account</h2>
//             <p style="color: #555555; font-size: 16px; margin-bottom: 30px; line-height: 1.5;">
//                 Use the verification code below to securely access your account. This code is valid for <strong>5 minutes</strong>.
//             </p>
//             <div style="background-color: #f8fafc; border: 2px dashed #cbd5e1; border-radius: 10px; padding: 20px; margin-bottom: 30px; display: inline-block;">
//                 <span style="font-size: 36px; font-weight: bold; color: #2563eb; letter-spacing: 6px;">${otp}</span>
//             </div>
//             <p style="color: #94a3b8; font-size: 13px;">If you didn't request this code, you can safely ignore this email.</p>
//         </div>
//     </div>
//     `;
// };